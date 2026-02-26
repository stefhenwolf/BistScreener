import Foundation

@MainActor
final class ScannerViewModel: ObservableObject {

    // MARK: - Published

    @Published var selectedIndex: IndexOption

    /// BUY-only tarama sonuçları (o an ekranda gösterilen)
    @Published var results: [ScanResult] = []

    @Published var isScanning: Bool = false
    @Published var progressText: String = ""
    @Published var progressValue: Double = 0
    @Published var errorText: String?

    /// Endeks bazlı RAM cache (EN GÜNCEL sonuçlar burada)
    @Published private(set) var resultsByIndex: [IndexOption: [ScanResult]] = [:]

    /// Endeks bazlı RAM "son kaydetme zamanı" (diskteki ile kıyas için)
    private var savedAtByIndex: [IndexOption: Date] = [:]

    // MARK: - User Filters (persisted)

    /// BUY-only preset (Relaxed/Normal/Strict)
    @Published var preset: TomorrowPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Keys.preset) }
    }

    /// Ultra preset (Sniper/Hunter/Scout)
    @Published var ultraPreset: UltraPreset = .hunter {
        didSet { UserDefaults.standard.set(ultraPreset.rawValue, forKey: Keys.ultraPreset) }
    }

    /// Strateji modu seçimi: Pre-Breakout veya Ultra Bounce
    @Published var strategyMode: ScanStrategyMode = .preBreakout {
        didSet { UserDefaults.standard.set(strategyMode.rawValue, forKey: Keys.strategyMode) }
    }

    /// 0 = all
    @Published var maxResults: Int {
        didSet {
            let clamped = max(0, maxResults)
            if clamped != maxResults { maxResults = clamped; return }
            UserDefaults.standard.set(maxResults, forKey: Keys.maxResults)
        }
    }

    private enum Keys {
        static let preset = BacktestKeys.scanPreset
        static let ultraPreset = BacktestKeys.ultraPreset
        static let strategyMode = BacktestKeys.strategyMode
        static let maxResults = "scan.maxResults"
    }

    // MARK: - Services (DI)

    private let services: AppServices

    // MARK: - Task control

    private var scanTask: Task<Void, Never>?
    private var activeUserKey: String = "guest"
    private var activeCloudUserID: String?

    // Auto-scan guard (projede dursun; çağırmazsan çalışmaz)
    private var lastAutoScanAt: Date? = nil
    private var lastAutoScanIndex: IndexOption? = nil

    // MARK: - Tuning knobs

    private let baseConcurrencyLimit: Int

    private let throttleAll  = AsyncThrottle(minInterval: 0.08)  // 0.25 -> 0.08
    private let throttle100  = AsyncThrottle(minInterval: 0.05)  // 0.18 -> 0.05
    private let throttle30   = AsyncThrottle(minInterval: 0.03)  // 0.15 -> 0.03

    private var concurrencyLimit: Int {
        switch selectedIndex {
        case .bistAll: return min(8, baseConcurrencyLimit)  // 2 -> 8
        case .xu100:   return min(12, baseConcurrencyLimit) // 6 -> 12
        case .xu030:   return min(16, baseConcurrencyLimit) // 8 -> 16
        }
    }

    private var throttle: AsyncThrottle {
        switch selectedIndex {
        case .bistAll: return throttleAll
        case .xu100:   return throttle100
        case .xu030:   return throttle30
        }
    }

    // MARK: - Init

    init(
        services: AppServices,
        defaultIndex: IndexOption = .bistAll,
        concurrencyLimit: Int = 8,
        preset: TomorrowPreset = .relaxed,
        maxResults: Int = 0
    ) {
        self.services = services
        self.selectedIndex = defaultIndex
        self.baseConcurrencyLimit = max(1, concurrencyLimit)

        let savedPresetRaw = UserDefaults.standard.string(forKey: Keys.preset)
        let savedMax = UserDefaults.standard.object(forKey: Keys.maxResults) as? Int
        let savedUltraRaw = UserDefaults.standard.string(forKey: Keys.ultraPreset)
        let savedModeRaw = UserDefaults.standard.string(forKey: Keys.strategyMode)

        self.preset = TomorrowPreset(rawValue: savedPresetRaw ?? "") ?? preset
        self.ultraPreset = UltraPreset(rawValue: savedUltraRaw ?? "") ?? .hunter
        self.strategyMode = ScanStrategyMode(rawValue: savedModeRaw ?? "") ?? .preBreakout
        self.maxResults = savedMax ?? maxResults

        self.maxResults = max(0, self.maxResults)
    }

    // MARK: - Public API

    /// Uygulama açılınca çağır: diskten EN GÜNCEL snapshot'ı bulur ve yükler.
    func loadLastSnapshotFromDisk() {
        var bestIndex: IndexOption?
        var bestSnap: PersistedScanSnapshot?

        for opt in IndexOption.allCases {
            if let snap = try? ScanSnapshotStore.load(forIndexRaw: opt.rawValue) {
                if let cur = bestSnap {
                    if snap.savedAt > cur.savedAt {
                        bestSnap = snap
                        bestIndex = opt
                    }
                } else {
                    bestSnap = snap
                    bestIndex = opt
                }
            }
        }

        guard let snap = bestSnap, let idx = bestIndex else {
            return
        }

        let converted = convertSnapshotToScanResults(snap)

        selectedIndex = idx
        results = converted
        resultsByIndex[idx] = converted
        savedAtByIndex[idx] = snap.savedAt

        progressText = "Son kayıt yüklendi: \(snap.savedAt.formatted(date: .abbreviated, time: .shortened))"
        progressValue = 1
        errorText = nil
    }

    func setUserContext(localUserKey: String?, cloudUserID: String?) {
        let cleanedLocal = sanitizeUserKey(localUserKey)
        let normalizedCloud = cloudUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCloud = (normalizedCloud?.isEmpty == false) ? normalizedCloud : nil
        guard cleanedLocal != activeUserKey || cleanedCloud != activeCloudUserID else { return }

        activeUserKey = cleanedLocal
        activeCloudUserID = cleanedCloud

        ScanSnapshotStore.setActiveUserKey(cleanedLocal)
        ScanStatsStore.shared.setActiveUserKey(cleanedLocal)

        cancelScan(silent: true)
        resultsByIndex.removeAll()
        savedAtByIndex.removeAll()
        results = []
        loadLastSnapshotFromDisk()
    }

    func deleteSnapshotAndReset() {
        try? ScanSnapshotStore.deleteAll()
        resultsByIndex.removeAll()
        savedAtByIndex.removeAll()
        results = []
        resetUI()
    }

    func resetUI() {
        cancelScan(silent: true)
        isScanning = false
        errorText = nil
        progressText = ""
        progressValue = 0
    }

    func startScanIfNeeded(cooldownSeconds: TimeInterval = 20) {
        if isScanning { return }
        if let t = lastAutoScanAt,
           Date().timeIntervalSince(t) < cooldownSeconds,
           lastAutoScanIndex == selectedIndex {
            return
        }
        lastAutoScanAt = Date()
        lastAutoScanIndex = selectedIndex
        startScan()
    }

    /// ✅ Endeks değişince RAM'de veri varsa diskten yükleyip EZME!
    func switchIndex(_ newIndex: IndexOption) {
        cancelScan(silent: true)
        isScanning = false
        progressText = ""
        progressValue = 0
        errorText = nil

        selectedIndex = newIndex

        // 1) RAM varsa: direkt onu göster
        if let mem = resultsByIndex[newIndex] {
            results = mem
            return
        }

        // 2) RAM yoksa: boş göster ve diskten yüklemeyi dene
        results = []
        loadLastResultsForSelectedIndex()
    }

    func startScan() {
        cancelScan(silent: true)
        pauseMarketTicker()

        let indexSnap = selectedIndex
        let indexCode = indexSnap.rawValue

        results = []
        errorText = nil
        progressValue = 0
        progressText = "Hazırlanıyor…"
        isScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isScanning = false
                self.resumeMarketTicker()
            }

            do {
                let snap = try await self.services.indexService.fetchSnapshot(indexCode: indexCode)
                let symbols = snap.yahooSymbols

                try Task.checkCancellation()

                guard !symbols.isEmpty else {
                    if self.selectedIndex == indexSnap {
                        self.errorText = "Sembol listesi boş geldi."
                        self.progressText = ""
                    }
                    return
                }

                await self.runScan(symbols: symbols, indexSnap: indexSnap)

            } catch is CancellationError {
                if self.selectedIndex == indexSnap {
                    self.progressText = "İptal edildi."
                    self.progressValue = 0
                }
            } catch {
                if !Task.isCancelled, self.selectedIndex == indexSnap {
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    /// RAM yoksa veya app açılışında diskten endeksin son snapshot’ını yükler.
    func loadLastResultsForSelectedIndex() {
        let idx = selectedIndex

        do {
            let snap = try ScanSnapshotStore.load(forIndexRaw: idx.rawValue)

            // Eğer RAM'de daha yeni bir sonuç varsa disk ile ezme
            if let memDate = savedAtByIndex[idx], memDate >= snap.savedAt,
               let mem = resultsByIndex[idx] {
                results = mem
                return
            }

            let converted = convertSnapshotToScanResults(snap)

            results = converted
            resultsByIndex[idx] = converted
            savedAtByIndex[idx] = snap.savedAt

            errorText = nil
            progressText = "Son kayıt yüklendi."
            progressValue = 1

        } catch {
            errorText = nil
            progressText = "Bu endeks için kayıt yok. Tara’ya bas."
            progressValue = 0
        }
    }

    func cancelScan(silent: Bool = false) {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        resumeMarketTicker()

        if !silent {
            progressText = "İptal edildi."
            progressValue = 0
        }
    }

    // MARK: - Scan engine

    private func runScan(symbols: [String], indexSnap: IndexOption) async {
        if self.selectedIndex != indexSnap {
            return
        }
        guard !Task.isCancelled else { return }

        // Debug sayaçlarını sıfırla
        resetScanDebugCounters()

        let total = symbols.count
        let sem = AsyncSemaphore(value: concurrencyLimit)
        let mode = self.strategyMode // capture before entering task group

        var localResults: [ScanResult] = []
        localResults.reserveCapacity(64)

        var completed = 0

        await withTaskGroup(of: ScanResult?.self) { group in
            defer { group.cancelAll() }

            for symbol in symbols {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    if Task.isCancelled { return nil }

                    await sem.wait()
                    await self.throttle.wait()

                    let result: ScanResult?
                    switch mode {
                    case .preBreakout:
                        result = await self.scanOneTomorrow(symbol: symbol)
                    case .ultraBounce:
                        result = await self.scanOneUltra(symbol: symbol)
                    }

                    await sem.signal()
                    return result
                }
            }

            for await res in group {
                if Task.isCancelled || self.selectedIndex != indexSnap {
                    group.cancelAll()
                    return
                }

                completed += 1

                if self.selectedIndex == indexSnap {
                    self.progressValue = Double(completed) / Double(max(total, 1))
                    self.progressText = "\(completed)/\(total) tarandı"
                }

                if let res { localResults.append(res) }

                // UI partial update (menos frequente para performance)
                if self.selectedIndex == indexSnap, (completed % 20 == 0 || completed == total) {
                    // apenas atualiza sem sort (sort acontece na view)
                    self.results = localResults
                }
            }
        }

        if Task.isCancelled {
            if self.selectedIndex == indexSnap {
                self.progressText = "İptal edildi."
                self.progressValue = 0
            }
            return
        }

        // maxResults en iyi skorlar üzerinden kesilsin (tamamlanma sırasına göre değil).
        localResults.sort {
            if $0.uiScore != $1.uiScore { return $0.uiScore > $1.uiScore }
            return $0.symbol < $1.symbol
        }

        // maxResults apply (0 = all)
        if maxResults > 0, localResults.count > maxResults {
            localResults = Array(localResults.prefix(maxResults))
        }

        // ✅ Debug özet (Xcode console)
        #if DEBUG
        let modeLabel = strategyMode == .ultraBounce ? "Ultra Bounce" : "Pre-Breakout"
        let presetLabel = strategyMode == .ultraBounce
            ? "\(ultraPreset.rawValue) | minScore: \(ultraPreset.config.minScore)"
            : "\(preset.rawValue) | minScore: \(preset.minBuyTotal)"
        print("""
        ═══════════════════════════════════════════
        📊 TARAMA ÖZET (\(indexSnap.title)) — \(modeLabel)
           Toplam sembol: \(total)
           Candle hatası: \(scanDebugCandleErrors)
           Az mum (<50): \(scanDebugLowCandles)
           Skor nil:     \(scanDebugScoreNil)
           ✅ BUY sinyal: \(scanDebugPassed)
           \(presetLabel)
        ═══════════════════════════════════════════
        """)
        #endif

        // ✅ RAM overwrite
        resultsByIndex[indexSnap] = localResults
        let savedAt = Date()
        savedAtByIndex[indexSnap] = savedAt

        // UI update only if still on same index
        if self.selectedIndex == indexSnap {
            self.results = localResults
            self.progressText = "Bitti. BUY: \(localResults.count)"
            self.progressValue = 1
        }

        // ✅ Persist (disk overwrite) - indexSnap!
        persistSnapshotAsync(indexSnap: indexSnap, universeCount: total, results: localResults, savedAt: savedAt)

        ScanStatsStore.shared.update(
            date: Date(),
            universeCount: total,
            matchesCount: localResults.count
        )
    }

    private func pauseMarketTicker() {
        services.ticker.stop()
        NotificationCenter.default.post(name: .pauseMarketTicker, object: nil)
    }

    private func resumeMarketTicker() {
        services.ticker.start()
        NotificationCenter.default.post(name: .resumeMarketTicker, object: nil)
    }

    // MARK: - Persist

    private func persistSnapshotAsync(indexSnap: IndexOption, universeCount: Int, results: [ScanResult], savedAt: Date) {
        Task.detached(priority: .utility) {
            let payload = PersistedScanSnapshot(
                savedAt: savedAt,
                indexRaw: indexSnap.rawValue,
                universeCount: universeCount,
                results: results.map { r in
                    PersistedScanResult(
                        symbol: r.symbol,
                        lastDate: r.lastDate,
                        lastClose: r.lastClose,
                        changePct: r.changePct,
                        patterns: r.patterns.map { p in
                            PersistedPatternScore(
                                name: p.pattern.rawValue,
                                score: Int(p.score),
                                direction: nil
                            )
                        },

                        // legacy
                        signalTotal: r.signalTotal,
                        signalDirection: r.signalDirection,
                        signalQuality: r.signalQuality,
                        signalConfidence: r.signalConfidence,
                        signal: r.signal,

                        // tomorrow
                        tomorrowTotal: r.tomorrowTotal,
                        tomorrowQuality: r.tomorrowQuality,
                        tomorrowTier: r.tomorrowTier,
                        tomorrowReasons: r.tomorrowReasons,
                        tomorrowBreakdown: r.tomorrowBreakdown
                    )
                }
            )

            try? ScanSnapshotStore.save(payload, forIndexRaw: indexSnap.rawValue)
        }
    }

    private func sanitizeUserKey(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "guest" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(chars)
        return out.isEmpty ? "guest" : out
    }

    // MARK: - Single symbol scan (Tomorrow BUY-only)

    // Debug sayaçları
    private var scanDebugCandleErrors = 0
    private var scanDebugLowCandles = 0
    private var scanDebugScoreNil = 0
    private var scanDebugPassed = 0

    private func resetScanDebugCounters() {
        scanDebugCandleErrors = 0
        scanDebugLowCandles = 0
        scanDebugScoreNil = 0
        scanDebugPassed = 0
        SignalScorer.resetDebugCounter()
    }

    private func scanOneTomorrow(symbol: String) async -> ScanResult? {
        do {
            let candles = try await loadCandlesForScan(symbol: symbol)

            guard candles.count >= 50 else {
                #if DEBUG
                if scanDebugLowCandles < 3 {
                    print("📊 \(symbol): az mum (\(candles.count))")
                }
                #endif
                scanDebugLowCandles += 1
                return nil
            }

            let recent = Array(candles.suffix(120)) // EMA50 + lookback + marj

            let last = recent[recent.count - 1]
            let prev = recent.count >= 2 ? recent[recent.count - 2] : last
            let changePct = ((last.close - prev.close) / max(prev.close, 0.000001)) * 100.0

            // patterns istersen UI'da göstermek için kalsın (opsiyonel)
            let scoredPatterns = PatternDetector.detectScored(last: Array(recent.suffix(60)))  // 120 -> 60

            let regime = MarketRegimeDetector.detect(from: recent)

            // ✅ Tomorrow BUY-only (v2: lookback preset'ten otomatik gelir)
            let tomo = SignalScorer.scoreTomorrowBuyOnly(
                candles: recent,
                preset: preset,
                regime: regime
            )

            guard let tomo else {
                scanDebugScoreNil += 1
                return nil
            }

            scanDebugPassed += 1

            let res = ScanResult(
                symbol: symbol,
                lastDate: last.date,
                lastClose: last.close,
                changePct: changePct,
                patterns: scoredPatterns,

                // tomorrow snapshot
                tomorrowTotal: tomo.total,
                tomorrowQuality: tomo.quality,
                tomorrowTier: tomo.tier,
                tomorrowReasons: tomo.reasons,
                tomorrowBreakdown: tomo.breakdown
            )

            return res

        } catch {
            #if DEBUG
            if scanDebugCandleErrors < 3 {
                print("📊 \(symbol): candle yükleme hatası: \(error.localizedDescription)")
            }
            #endif
            scanDebugCandleErrors += 1
            return nil
        }
    }

    // MARK: - Single symbol scan (Ultra Bounce)

    private func scanOneUltra(symbol: String) async -> ScanResult? {
        do {
            let candles = try await loadCandlesForScan(symbol: symbol)

            guard candles.count >= 60 else {
                #if DEBUG
                if scanDebugLowCandles < 3 {
                    print("📊 \(symbol): az mum (\(candles.count)) [Ultra]")
                }
                #endif
                scanDebugLowCandles += 1
                return nil
            }

            let recent = Array(candles.suffix(120))
            let last = recent[recent.count - 1]
            let prev = recent.count >= 2 ? recent[recent.count - 2] : last
            let changePct = ((last.close - prev.close) / max(prev.close, 0.000001)) * 100.0

            let scoredPatterns = PatternDetector.detectScored(last: Array(recent.suffix(60)))
            let regime = MarketRegimeDetector.detect(from: recent)

            // Ultra Bounce scoring
            let ultra = UltraSignalScorer.score(
                candles: recent,
                config: ultraPreset.config,
                regime: regime
            )

            guard let ultra else {
                scanDebugScoreNil += 1
                return nil
            }

            scanDebugPassed += 1

            return ScanResult(
                symbol: symbol,
                lastDate: last.date,
                lastClose: last.close,
                changePct: changePct,
                patterns: scoredPatterns,
                tomorrowTotal: ultra.total,
                tomorrowQuality: ultra.quality,
                tomorrowTier: ultra.tier,
                tomorrowReasons: ultra.reasons,
                tomorrowBreakdown: ultra.breakdown
            )

        } catch {
            #if DEBUG
            if scanDebugCandleErrors < 3 {
                print("📊 \(symbol): candle hatası [Ultra]: \(error.localizedDescription)")
            }
            #endif
            scanDebugCandleErrors += 1
            return nil
        }
    }

    /// CandleRepository üzerinden yükler:
    /// cache kullanır, ama veri günü gerideyse latest refresh de dener.
    private func loadCandlesForScan(symbol: String) async throws -> [Candle] {
        let sym = symbol.normalizedBISTSymbol()

        try Task.checkCancellation()

        return try await services.candles.getCandles(
            symbol: sym,
            range: .mo6,
            minCount: 50,
            forceRefresh: false
        )
    }

    // MARK: - Convert snapshot

    private func convertSnapshotToScanResults(_ snap: PersistedScanSnapshot) -> [ScanResult] {
        snap.results.compactMap { r in
            let patterns: [CandlePatternScore] = r.patterns.compactMap { ps in
                guard let pat = CandlePattern(rawValue: ps.name) else { return nil }
                return CandlePatternScore(pattern: pat, score: ps.score)
            }

            // BUY-only: snapshot'ta tomorrowTotal yoksa listede göstermeyebiliriz.
            // Ama disk yükleyince yine de istersen hepsini göstermek yerine sadece BUY yükle:
            if r.tomorrowTotal == nil { return nil }

            return ScanResult(
                symbol: r.symbol,
                lastDate: r.lastDate,
                lastClose: r.lastClose,
                changePct: r.changePct,
                patterns: patterns,

                // legacy
                signalTotal: r.signalTotal,
                signalDirection: r.signalDirection,
                signalQuality: r.signalQuality,
                signalConfidence: r.signalConfidence,
                signal: r.signal,

                // tomorrow
                tomorrowTotal: r.tomorrowTotal,
                tomorrowQuality: r.tomorrowQuality,
                tomorrowTier: r.tomorrowTier,
                tomorrowReasons: r.tomorrowReasons,
                tomorrowBreakdown: r.tomorrowBreakdown
            )
        }
    }
}
