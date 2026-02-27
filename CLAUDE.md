# CLAUDE.md

Bu dosya, Claude Code ile bu projede verimli çalışmak için kısa rehberdir.

## Proje Özeti

- Platform: iOS (Swift / SwiftUI)
- Ana hedef: BIST hisseleri için screener + teknik analiz akışları
- Xcode proje dosyası: `BistScreener.xcodeproj`

## Geliştirme Notları

- Büyük refactor öncesi küçük ve atomik commit yap.
- UI değişikliklerinde mümkünse ilgili ViewModel/Store testlerini de güncelle.
- Ağ/servis katmanı değişikliklerinde hata yönetimini (`Result`, fallback, timeout) koru.

## Dizinler (yüksek seviye)

- `BistScreener/` → uygulama hedefi
- `Views/`, `ViewModels/`, `Stores/`, `Services/`, `Models/` → ana katmanlar
- `BistScreenerTests/`, `BistScreenerUITests/` → testler
- `functions/`, `firebase/`, `dataconnect/` → backend/entegrasyon tarafı

## Claude ile çalışma akışı

1. İstenen değişiklik için önce ilgili dosyaları tara.
2. Gerekirse küçük bir plan çıkar.
3. En küçük güvenli adımlarla kodu güncelle.
4. Derleme/test komutlarını çalıştır.
5. Kısa, net commit mesajı yaz.

## Faydalı Komutlar

```bash
# Repo durumu
git status

# Son commitler
git log --oneline -n 10

# Değişen dosyalar
git diff --name-only
```

## Not

Bu repo içinde `.claude/worktrees/*` klasörleri yerel Claude çalışma akışının parçası olabilir.
Gerekmedikçe silme/temizleme yapma.
