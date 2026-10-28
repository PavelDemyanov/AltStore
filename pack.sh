#!/bin/sh
# Сборка AltStore 2.3.1 с исправлением входа (HTTP 503) в IPA для AltServer → Sideload .ipa.
# Проверено с Xcode 27.1. Результат — build/AltStore-2.3.1-signin-fix.ipa.
set -e
cd "$(dirname "$0")"
mkdir -p build

# Новый компоновщик Xcode не принимает Dependencies/libcurl/libcurl.a: члены архива не выровнены на 8 байт
# (старый ld_classic это терпел, в Xcode 27 его нет). Пересобираем срез arm64 из тех же объектов на время
# сборки и возвращаем исходный файл.
CURL=Dependencies/libcurl/libcurl.a
cp "$CURL" build/libcurl.orig.a
trap 'cp build/libcurl.orig.a "$CURL"' EXIT
rm -rf build/libcurl && mkdir -p build/libcurl/o
lipo -thin arm64 build/libcurl.orig.a -output build/libcurl/arm64.a
(cd build/libcurl/o && ar -x ../arm64.a)
xcrun libtool -static -o "$CURL" build/libcurl/o/*.o 2>/dev/null

# Xcode 27 не собирает под iOS ниже 15, а у зависимостей стоит 12–14; сам AltStore требует 17.4.
xcodebuild -workspace AltStore.xcworkspace -scheme AltStore -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  IPHONEOS_DEPLOYMENT_TARGET=17.4 build > build/build.log 2>&1 || { grep -E "error:" build/build.log | sort -u | head; exit 1; }

# Права (группа приложений и т. п.) — из официального IPA: AltServer запрашивает у Apple то, что записано в подписи.
A=build/dd/Build/Products/Release-iphoneos/AltStore.app
W=build/official
if [ ! -d "$W/Payload" ]; then
  mkdir -p "$W"
  curl -sL -o "$W/AltStore.ipa" https://cdn.altstore.io/file/altstore/apps/altstore/2_3_1.ipa
  (cd "$W" && unzip -q AltStore.ipa)
fi
codesign -d --entitlements - --xml "$W/Payload/AltStore.app" > "$W/app.ent" 2>/dev/null
codesign -d --entitlements - --xml "$W/Payload/AltStore.app/PlugIns/AltWidgetExtension.appex" > "$W/widget.ent" 2>/dev/null

for f in "$A"/Frameworks/*; do codesign -f -s - "$f" 2>/dev/null; done
codesign -f -s - --entitlements "$W/widget.ent" "$A/PlugIns/AltWidgetExtension.appex" 2>/dev/null
codesign -f -s - --entitlements "$W/app.ent" "$A" 2>/dev/null
codesign --verify --deep --strict "$A"

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$A" build/ipa/Payload/
rm -f build/AltStore-2.3.1-signin-fix.ipa
(cd build/ipa && zip -qry ../AltStore-2.3.1-signin-fix.ipa Payload)
ls -la build/AltStore-2.3.1-signin-fix.ipa
