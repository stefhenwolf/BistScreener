# Firestore Schema (BistScreener)

Bu şema kullanıcı bazlı strateji + portföy + favoriler + tarama verisini backend'e taşımak için hazırlanmıştır.

## 1) Koleksiyon Yapısı

- `users/{uid}/strategyState/live`
- `users/{uid}/strategyEvents/{eventId}`
- `users/{uid}/portfolioPositions/{positionId}`
- `users/{uid}/watchlist/state`
- `users/{uid}/scanSnapshots/{indexRaw}`
- `users/{uid}/scanState/stats`

`uid` değeri Firebase Auth `request.auth.uid` olmalıdır.

## 2) strategyState/live

Amaç: Canlı stratejinin tek güncel snapshot'ı.

Önerilen alanlar:
- `schemaVersion` (Number)
- `updatedAt` (String ISO-8601 UTC)
- `updatedAtEpoch` (Number, unix seconds)
- `isRunning` (Bool)
- `startedAt` (String ISO-8601 UTC, nullable)
- `lastUpdated` (String ISO-8601 UTC, nullable)
- `sourceSnapshotDate` (String ISO-8601 UTC, nullable)
- `initialCapitalTL` (Number)
- `cashTL` (Number)
- `settings` (Map)
- `holdings` (Array<Map>)
- `pendingActions` (Array<Map>)
- `skipBuyUntil` (String ISO-8601 UTC, nullable)
- `lastBuyWindowRunAt` (String ISO-8601 UTC, nullable)

## 3) strategyEvents/{eventId}

Amaç: İşlem logu (audit trail).

Önerilen alanlar:
- `id` (String UUID)
- `date` (String ISO-8601 UTC)
- `dateEpoch` (Number, unix seconds; query/sort için)
- `kind` (`buy` | `sell` | `skip`)
- `symbol` (String)
- `amountTL` (Number)
- `cashAfterTL` (Number)
- `note` (String)
- `holdingsText` (String)

Örnek sorgu:
- Son 100 olay: `orderBy("dateEpoch", "desc").limit(100)`

## 4) portfolioPositions/{positionId}

Amaç: Kullanıcının strateji sonrası/manuel portföy varlıkları.

Önerilen alanlar (Asset modeli):
- `id` (String UUID)
- `type` (`stock` | `fund` | `fx` | `metal` | `crypto`)
- `name` (String)
- `symbol` (String)
- `quantity` (Number)
- `avgCostTRY` (Number, nullable)
- `createdAt` (String ISO-8601 UTC)
- `updatedAtEpoch` (Number)

## 5) Tarih ve Saat Standardı

- Backend yazımları **UTC ISO-8601** formatında tutulmalı.
- UI'da gösterim lokal timezone'a çevrilmeli.
- İşlem zamanı alanları:
  - `createdAt`: kayıt oluşumu
  - `updatedAt`: son güncelleme
  - `executedAt` (opsiyonel): onaylanan işlemin gerçek gerçekleşme zamanı
  - `marketDate` (opsiyonel): piyasa günü bazlı raporlama

## 6) watchlist/state

Amaç: Kullanıcı favori sembol listesi.

Alanlar:
- `symbols` (Array<String>)
- `updatedAtEpoch` (Number)

## 7) scanSnapshots/{indexRaw}

Amaç: Endeks bazlı son tarama snapshot'ı.

Alanlar:
- `savedAt` (String ISO-8601 UTC)
- `savedAtEpoch` (Number)
- `indexRaw` (`bist_all` | `xu100` | `xu030`)
- `universeCount` (Number)
- `results` (Array<Map>)
- `updatedAtEpoch` (Number)

## 8) scanState/stats

Amaç: Tarama özet metrikleri.

Alanlar:
- `lastScanDate` (String ISO-8601 UTC, nullable)
- `lastUniverseCount` (Number)
- `lastMatchesCount` (Number)
- `updatedAt` (String ISO-8601 UTC)
- `updatedAtEpoch` (Number)

## 9) Entegrasyon Notları

Kod tarafında hazır repository:
- `BistScreener/CloudDataRepository.swift`

İçerik:
- `CloudDataRepository` protocol
- `StrategyCloudSnapshot` DTO
- `FirestoreCloudDataRepository` (FirebaseFirestore mevcutsa)
- `NoopCloudDataRepository` (fallback)

## 10) Güvenlik

- Rules dosyası: `firebase/firestore.rules`
- Kullanıcı yalnızca kendi `uid` altını okuyup yazabilir.
- Minimum alan doğrulaması `hasAll` ile yapılır.

## 11) Sonraki Adım (Öneri)

- `AuthSessionStore` tarafında Firebase Auth `uid` alınmalı.
- `LiveStrategyStore.persist()` ve event append noktalarında `CloudDataRepository` çağrısı eklenmeli.
- Çakışma yönetimi için `updatedAtEpoch` ile last-write-wins veya versiyonlama uygulanmalı.
