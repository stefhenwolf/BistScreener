//
//  BorsaIstanbulIndexService.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

final class BorsaIstanbulIndexService {

    struct Snapshot {
        let indexCode: String
        let date: Date
        let yahooSymbols: [String]
    }

    private let url = URL(string: "https://www.borsaistanbul.com/datum/hisse_endeks_ds.csv")!

    func fetchSnapshot(indexCode: String) async throws -> Snapshot {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Encoding fallback
        let text =
            String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1254)
            ?? String(decoding: data, as: UTF8.self)

        let lines = text
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard !lines.isEmpty else {
            return Snapshot(indexCode: indexCode, date: .distantPast, yahooSymbols: [])
        }

        // Delimiter auto-detect
        let first = lines.first ?? ""
        let candidates: [Character] = [";", ",", "\t"]
        let delimiter: Character = candidates
            .map { d in (d, first.filter { $0 == d }.count) }
            .max(by: { $0.1 < $1.1 })?.0 ?? ";"

        func split(_ line: String) -> [String] {
            line.split(separator: delimiter, omittingEmptySubsequences: false).map { String($0) }
        }

        // Normalize: TR upper + remove diacritics + keep alphanumerics
        func normalize(_ s: String) -> String {
            let tr = Locale(identifier: "tr_TR")
            var x = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: tr)

            // BOM / zero-width gibi saçmalıkları temizle
            x = x
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")

            x = x
                .replacingOccurrences(of: "İ", with: "I")
                .replacingOccurrences(of: "İ", with: "I")
                .replacingOccurrences(of: "Ş", with: "S")
                .replacingOccurrences(of: "Ğ", with: "G")
                .replacingOccurrences(of: "Ü", with: "U")
                .replacingOccurrences(of: "Ö", with: "O")
                .replacingOccurrences(of: "Ç", with: "C")

            let allowed = CharacterSet.alphanumerics
            return x.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        }

        // Header detect
        let h0 = split(lines[0])
        let h1 = lines.count > 1 ? split(lines[1]) : []
        let knownKeys = ["BILESENKODU", "CONSTITUENTCODE", "ENDEKSKODU", "INDEXCODE", "TARIH", "DATE"]

        func scoreHeader(_ h: [String]) -> Int {
            let set = Set(h.map(normalize))
            return knownKeys.reduce(0) { $0 + (set.contains($1) ? 1 : 0) }
        }

        let header = scoreHeader(h1) > scoreHeader(h0) ? h1 : h0
        let normHeader = header.map(normalize)

        func findIndex(exact candidates: [String]) -> Int? {
            let c = Set(candidates.map(normalize))
            return normHeader.firstIndex(where: { c.contains($0) })
        }

        func findIndex(prefixes: [String]) -> Int? {
            let p = prefixes.map(normalize)
            return normHeader.firstIndex(where: { key in p.contains(where: { key.hasPrefix($0) }) })
        }

        guard
            let idxComp  = findIndex(exact: ["BILESEN KODU", "CONSTITUENT CODE"]),
            let idxIndex = findIndex(exact: ["ENDEKS KODU", "INDEX CODE"]),
            let idxDate  = findIndex(prefixes: ["TARIH", "DATE"])
        else {
            print("CSV header:", header)
            throw NSError(
                domain: "BorsaIstanbulCSV",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CSV kolonları beklenen formatta değil (başlık değişmiş olabilir)."]
            )
        }

        // Date parsing
        let df1 = DateFormatter(); df1.locale = Locale(identifier: "tr_TR"); df1.dateFormat = "dd/MM/yyyy"
        let df2 = DateFormatter(); df2.locale = Locale(identifier: "tr_TR"); df2.dateFormat = "dd.MM.yyyy"

        func parseDate(_ s: String) -> Date? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return df1.date(from: t) ?? df2.date(from: t)
        }

        // ✅ normalize indexCode once
        let wantedIndex = normalize(indexCode)

        // ✅ BIST (Tümü) modu: index filtresi yok
        let scanAll: Bool = {
            let w = wantedIndex
            return w == "BIST" || w == "BISTALL" || w == "BIST_ALL" || w == "ALL"
        }()

        var maxDate: Date = .distantPast
        var bucketByDate: [Date: [String]] = [:]
        var matchedRowCount = 0

        for line in lines {
            // header satırlarını atla
            let up = normalize(line)
            if up.contains("BILESENKODU") || up.contains("CONSTITUENTCODE") { continue }

            let parts = split(line)
            guard parts.count > max(idxComp, idxIndex, idxDate) else { continue }

            let rowIndexRaw = parts[idxIndex]
            let rowIndexNorm = normalize(rowIndexRaw)

            // ✅ Eğer BIST (Tümü) değilsek index filtresi uygula
            if !scanAll {
                guard rowIndexNorm == wantedIndex else { continue }
            }

            guard let d = parseDate(parts[idxDate]) else { continue }

            let rawComp = parts[idxComp].trimmingCharacters(in: .whitespacesAndNewlines)
            let base = rawComp.split(separator: ".").first.map(String.init) ?? rawComp
            guard !base.isEmpty else { continue }

            matchedRowCount += 1

            if d > maxDate { maxDate = d }
            bucketByDate[d, default: []].append(base)
        }

        // ✅ Debug
        if scanAll {
            print("BIST_ALL matchedRows=\(matchedRowCount) latestDate=\(maxDate)")
        } else {
            print("Index \(indexCode) matchedRows=\(matchedRowCount) latestDate=\(maxDate)")
        }

        let bases = Array(Set(bucketByDate[maxDate] ?? [])).sorted()
        let yahoo = bases.map { "\($0).IS" }

        return Snapshot(indexCode: indexCode, date: maxDate, yahooSymbols: yahoo)
    }
}
