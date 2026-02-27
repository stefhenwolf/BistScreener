#!/usr/bin/env bash
set -euo pipefail

# BistScreener README screenshot helper
# - Boots simulator
# - Builds & runs app on simulator
# - Captures 5 screenshots with guided prompts

PROJECT_PATH="BistScreener.xcodeproj"
SCHEME="BistScreener"
CONFIG="Debug"
DESTINATION_NAME="iPhone 16 Pro"
OUTPUT_DIR="Docs/screenshots"

mkdir -p "$OUTPUT_DIR"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun bulunamadı. Xcode Command Line Tools kurulu olmalı." >&2
  exit 1
fi

SIM_UDID="$(xcrun simctl list devices available | awk -F '[()]' -v name="$DESTINATION_NAME" '$0 ~ name {print $2; exit}')"
if [[ -z "${SIM_UDID:-}" ]]; then
  echo "Simulator bulunamadı: $DESTINATION_NAME" >&2
  echo "Mevcut cihazları görmek için: xcrun simctl list devices available" >&2
  exit 1
fi

echo "[1/6] Simulator açılıyor: $DESTINATION_NAME ($SIM_UDID)"
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b

echo "[2/6] Uygulama build ediliyor..."
xcodebuild -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$SIM_UDID" \
  build >/tmp/bistscreener-build.log

echo "[3/6] Uygulama bundle id ayarlanıyor..."
APP_BUNDLE_ID="com.sedat.BistScreener"

echo "[4/6] Uygulama launch ediliyor: $APP_BUNDLE_ID"
xcrun simctl launch "$SIM_UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

capture() {
  local file="$1"
  local prompt="$2"
  echo ""
  echo "➡️  $prompt"
  read -r -p "Hazır olunca Enter'a bas... " _
  xcrun simctl io "$SIM_UDID" screenshot "$OUTPUT_DIR/$file"
  echo "✅ Kaydedildi: $OUTPUT_DIR/$file"
}

echo "[5/6] Rehberli screenshot alma başlıyor"
capture "01-home.png" "Ana liste/screener ekranına gel"
capture "02-filters.png" "Filtreler ekranına gel"
capture "03-detail.png" "Hisse detay ekranına gel"
capture "04-signal-breakdown.png" "Sinyal kırılımı ekranına gel"
capture "05-watchlist.png" "Favoriler/izleme ekranına gel"

echo ""
echo "[6/6] Tamamlandı 🎉"
echo "Dosyalar: $OUTPUT_DIR"
echo "Git'e eklemek için: git add Docs/screenshots/*.png && git commit -m 'Add app screenshots' && git push"
