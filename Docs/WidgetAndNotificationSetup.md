# Widget + Strateji Onay Bildirimleri Kurulum

## 1) App Group

- Xcode > target **BistScreener** > Signing & Capabilities > `+ Capability` > **App Groups**
- Group ekle: `group.com.sedat.bistscreener`

> Kod tarafında bu group id kullanılıyor.

## 2) Bildirim izinleri

- Uygulama açıldığında izin penceresi otomatik gelir.
- Kullanıcı izin vermezse strateji onayları sadece uygulama içinden onaylanır.

## 3) Widget Extension ekleme

Bu repoda widget kodu hazır:

- `BistScreenerWidgets/BistScreenerWidgets.swift`
- `BistScreenerWidgets/WidgetSharedModels.swift`

Xcode’da:

1. File > New > Target > **Widget Extension**
2. Target adı: `BistScreenerWidgets`
3. Oluşan otomatik dosyaları silip yukarıdaki iki dosyayı widget target’ına ekle
4. Widget target’ında da **App Groups** capability ekle ve aynı group’u seç: `group.com.sedat.bistscreener`
5. Ana uygulama + widget target birlikte build al

## 4) Deep link yönlendirme

Widget tıklaması aşağıdaki ekranlara gider:

- `bistscreener://profile/assets`
- `bistscreener://profile/strategy`

Bu URL scheme (`bistscreener`) uygulamanın `Info.plist` dosyasına eklenmiştir.
