# BistScreener

BistScreener, **Borsa İstanbul (BIST)** hisselerini teknik göstergelerle analiz etmeyi ve filtrelemeyi kolaylaştıran bir iOS uygulamasıdır.

Uygulama; hisse listesini tarama, teknik sinyal üretimi, detay ekranları ve izleme akışlarını tek bir yerde toplar.

## Öne Çıkan Özellikler

- 📈 **Hisse tarama (screener)**
  - Teknik koşullara göre filtreleme
  - Sinyal bazlı listeleme
- 🧠 **Teknik analiz altyapısı**
  - İndikatör hesaplamaları
  - Mum (candle) verisi üzerinden değerlendirme
- 🔎 **Hisse detay ekranı**
  - Sinyal kırılımı (signal breakdown)
  - Teknik verilerin daha detaylı görünümü
- 🧱 **Katmanlı mimari**
  - `Views`, `ViewModels`, `Stores`, `Services`, `Models` ayrımı
- ☁️ **Backend/servis entegrasyonu**
  - Firebase / Functions / DataConnect tarafı için proje dosyaları
- 🧪 **Test altyapısı**
  - Unit test ve UI test hedefleri

## Proje Yapısı

```text
BistScreener/
├─ BistScreener/              # iOS app target
├─ Views/                     # SwiftUI ekranları
├─ ViewModels/                # Sunum mantığı
├─ Stores/                    # Durum yönetimi
├─ Services/                  # Ağ / servis katmanı
├─ Models/                    # Domain modelleri
├─ Components/                # Yeniden kullanılabilir UI parçaları
├─ BistScreenerTests/         # Unit testler
├─ BistScreenerUITests/       # UI testler
├─ functions/                 # Backend functions
├─ firebase/                  # Firebase konfigürasyonları
└─ dataconnect/               # DataConnect dosyaları
```

## Teknolojiler

- **Swift / SwiftUI**
- **Xcode Project** (`BistScreener.xcodeproj`)
- **Firebase ekosistemi** (projede ilgili yapılandırmalar mevcut)

## Kurulum

1. Repoyu klonlayın:

```bash
git clone https://github.com/stefhenwolf/BistScreener.git
cd BistScreener
```

2. Projeyi Xcode ile açın:

```bash
open BistScreener.xcodeproj
```

3. Gerekli yerel ayarları (sertifika/provisioning/Firebase plist vb.) kendi ortamınıza göre tamamlayın.

4. Uygulamayı simulator veya gerçek cihazda çalıştırın.

## Geliştirme Notları

- Geniş çaplı değişikliklerde küçük ve atomik commit tercih edin.
- UI değişikliklerinde mümkünse ilgili testleri güncelleyin.
- Projede yer alan `.claude/worktrees/*` klasörleri yerel geliştirme akışının parçası olabilir; gereksiz temizleme yapmayın.

## Ekran Görüntüleri

> Aşağıdaki görselleri `Docs/screenshots/` klasörüne ekleyerek README’de otomatik gösterimi kullanabilirsiniz.

### Ana Akışlar

| Ekran | Görsel |
|---|---|
| Ana liste / Screener | ![Ana liste](Docs/screenshots/01-home.png) |
| Filtreler | ![Filtreler](Docs/screenshots/02-filters.png) |
| Hisse detay | ![Hisse detay](Docs/screenshots/03-detail.png) |
| Teknik sinyal kırılımı | ![Signal breakdown](Docs/screenshots/04-signal-breakdown.png) |
| Favoriler / İzleme | ![Favoriler](Docs/screenshots/05-watchlist.png) |

### Hızlı Ekleme Rehberi

1. Ekran görüntülerini alın (iPhone simulator önerilir).
2. Dosyaları şu isimlerle kaydedin:
   - `Docs/screenshots/01-home.png`
   - `Docs/screenshots/02-filters.png`
   - `Docs/screenshots/03-detail.png`
   - `Docs/screenshots/04-signal-breakdown.png`
   - `Docs/screenshots/05-watchlist.png`
3. Commit + push sonrası görseller README üzerinde görünecektir.

## Yol Haritası (Öneri)

- [ ] Gelişmiş filtre kombinasyonları
- [ ] Alarm/uyarı sistemi (fiyat veya sinyal tetikleme)
- [ ] Daha kapsamlı performans optimizasyonu
- [ ] Ekran görüntüleri ve demo GIF ekleme

## Katkı

PR ve issue açarak katkıda bulunabilirsiniz.

## Lisans

Henüz lisans dosyası eklenmedi. Gerekirse `LICENSE` dosyası ile lisans netleştirilecektir.
