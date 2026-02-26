# App Store Release Checklist (BistScreener)

## 1) Kimlik Doğrulama ve Veri Güvenliği
- `E-posta/Şifre` için şifreyi cihazda **asla** saklama.
- Oturum (session/user token) saklanacaksa `Keychain` kullan.
- `Remember Me` açık: oturumu Keychain’de tut.
- `Remember Me` kapalı: uygulama kapanınca oturumu sil.
- Şifre sıfırlama gerçek backend ile yapılmalı (`/forgot-password`).
- Apple/Google girişlerinde sadece kullanıcı kimliği + kısa profil bilgisini sakla.

## 2) Google / Apple Sign-In
- Apple Sign In: App Store için zorunlu olduğu senaryolarda aktif olmalı.
- Google Sign In:
  - `GoogleSignIn` SDK ekle.
  - `Info.plist` içine gerçek `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` koy.
  - URL scheme doğrula.
- Çalışmayan provider butonlarını release’te gizle veya disabled + açıklama ver.

## 3) Info.plist ve Gizlilik
- Placeholder değer bırakma (`YOUR_...` değerlerini gerçek değerlerle değiştir).
- Gerekli izin açıklamaları varsa ekle (kamera, fotoğraf vb. kullanılıyorsa).
- Gizlilik politikası URL’si hazır olmalı.
- App Privacy (App Store Connect) formunu doldur:
  - Hangi veri toplanıyor?
  - Hesapla ilişkilendiriliyor mu?
  - Takip için kullanılıyor mu?

## 4) Uygulama Kalitesi
- Tüm ana akışlar test:
  - Login (manuel/apple/google)
  - Logout
  - Remember Me
  - Strateji başlat/durdur
  - Onaylı al/sat
- Zayıf ağda test (timeout, retry, hata mesajları).
- Uygulama çökmesi için Crash test + kritik ekranlarda uzun kullanım testi.

## 5) UI/UX Hazırlığı
- App icon set tam ve doğru boyutlarda.
- Launch ve navigation geçişleri stabil.
- Türkçe metinlerde yazım kontrolü.
- Boş durumlar/hata durumları kullanıcıya net mesaj veriyor mu kontrol et.

## 6) Sürümleme ve İmzalama
- `Version` (Marketing) artır.
- `Build` numarası artır.
- Release configuration ile archive al.
- Doğru Team / Bundle ID / Provisioning profile doğrula.

## 7) App Store Connect Hazırlığı
- Uygulama adı, kısa açıklama, uzun açıklama.
- Anahtar kelimeler.
- Ekran görüntüleri (iPhone + iPad gerekiyorsa).
- Destek URL / gizlilik URL.
- Age rating ve compliance soruları.

## 8) Son Teknik Kontrol (Upload Öncesi)
- Release build local cihazda denerken:
  - Login sonrası cold start davranışı
  - Remember Me açık/kapalı davranışı
  - Oturum silme sonrası login ekranına dönüş
- Debug loglarını azalt.
- Test kullanıcıları ve demo hesapları hazırlıksa not et.

## 9) Giriş Verisi Saklama İçin Önerilen Mimari (Prod)
- Backend JWT/OAuth token üretir.
- `Access Token` kısa ömür, `Refresh Token` daha uzun ömür.
- `Refresh Token` Keychain’de tutulur.
- Oturum yenileme başarısızsa kullanıcı login ekranına düşürülür.
- Şifre sadece giriş anında backend’e gönderilir; cihazda tutulmaz.

## 10) Bu Projedeki Durum (Mevcut)
- Oturum saklama: `Keychain` (Remember Me ile).
- Şifre saklama: yok.
- Manuel giriş: local doğrulama (demo amaçlı).
- Prod için backend auth katmanı eklenmesi gerekir.

## 11) Bu Güncelleme ile Gelenler
- Giriş ekranında zorunlu:
  - Gizlilik Politikası onayı
  - Kullanım Koşulları onayı
- `Info.plist` anahtarları:
  - `PRIVACY_POLICY_URL`
  - `TERMS_OF_USE_URL`
- Profil ekranında:
  - `Hesabı Sil` (manual hesap için cihazdaki kayıtlı üyeliği kalıcı siler)
  - `Cihaz Verisini Temizle` (oturum + local auth verisi temizler)
- Şifre hash:
  - SHA-256 + uygulama içi pepper ile saklanır.

## 12) Release Öncesi Zorunlu Değerler
- `Info.plist` placeholder URL'lerini gerçek adreslerle değiştir:
  - `https://example.com/privacy`
  - `https://example.com/terms`
- Google sign-in için gerçek client değerleri gir:
  - `GOOGLE_CLIENT_ID`
  - `GOOGLE_REVERSED_CLIENT_ID`
- App Store Connect'e aynı URL'leri ekle:
  - Privacy Policy URL
  - Terms of Use (EULA veya custom terms) URL

## 13) Veri Saklama Politikası (Önerilen)
- Cihazda saklanan:
  - Oturum özeti (`AuthUser`) -> Keychain
  - Manual demo hesap kaydı -> Keychain
- Cihazda saklanmayan:
  - Düz şifre
- Hesap silme sonrası:
  - Oturum, profil mirror bilgileri ve manual hesap kaydı silinir.
- Prod backend geçişinde:
  - Hesap silme endpoint'i ile sunucu tarafı silme zorunlu.
  - Veri saklama süresi (retention) ve silme SLA metne bağlanmalı.
