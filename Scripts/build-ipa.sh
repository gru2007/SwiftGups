#!/usr/bin/env bash
#
# Собирает неподписанный .ipa, пригодный для LiveContainer.
#
# LiveContainer запускает гостевые приложения сам и подписывает их
# сертификатом пользователя (или работает JIT-less), поэтому сборка идёт
# без подписи: CODE_SIGNING_ALLOWED=NO. Побочный эффект — entitlements
# в бинарник не попадают, значит iCloud/CloudKit, App Groups и пуши
# в такой сборке не работают, пока LiveContainer не выдаст свои.
#
# Использование:
#   Scripts/build-ipa.sh
#   BUILD_NUMBER=42 Scripts/build-ipa.sh
#   KEEP_PLUGINS=0 Scripts/build-ipa.sh     # выкинуть виджет/Live Activity
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="${PROJECT:-SwiftGups.xcodeproj}"
SCHEME="${SCHEME:-SwiftGups}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/.build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.build/artifacts}"
# Виджет с Live Activity в LiveContainer чаще всего не заводится, но и не мешает
# приложению стартовать, поэтому по умолчанию оставляем его в бандле.
KEEP_PLUGINS="${KEEP_PLUGINS:-1}"
# Номер сборки: если задан, перезаписывает CFBundleVersion в готовом бандле.
BUILD_NUMBER="${BUILD_NUMBER:-}"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild не найден — нужен macOS с Xcode."

log "Окружение"
xcodebuild -version
echo "Схема:        $SCHEME ($CONFIGURATION)"
echo "DerivedData:  $DERIVED_DATA"

# Одна точка правды для build и showBuildSettings: если списки флагов разойдутся,
# xcodebuild посчитает это разными конфигурациями и полезет пересобирать.
XCODE_FLAGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -derivedDataPath "$DERIVED_DATA"
  -skipPackagePluginValidation
  -skipMacroValidation
)

BUILD_SETTINGS=(
  ONLY_ACTIVE_ARCH=NO
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  CODE_SIGN_ENTITLEMENTS=""
  DEVELOPMENT_TEAM=""
  PROVISIONING_PROFILE_SPECIFIER=""
)

STAGE="$(mktemp -d)"
SETTINGS_FILE="$(mktemp)"
trap 'rm -rf "$STAGE" "$SETTINGS_FILE"' EXIT

log "Сборка"
xcodebuild "${XCODE_FLAGS[@]}" "${BUILD_SETTINGS[@]}" build

# Путь к бандлу спрашиваем у самого xcodebuild. Угадывать нельзя: рядом в
# products-каталоге лежат ещё App Clip и виджет, а настройки схемы могут
# переехать в любой момент.
log "Поиск собранного бандла"
xcodebuild "${XCODE_FLAGS[@]}" "${BUILD_SETTINGS[@]}" -showBuildSettings -json >"$SETTINGS_FILE" 2>/dev/null

read -r PRODUCTS_DIR PRODUCT_NAME <<< "$(
  SETTINGS_FILE="$SETTINGS_FILE" TARGET="$SCHEME" python3 - <<'PY'
import json, os, sys

raw = open(os.environ["SETTINGS_FILE"], encoding="utf-8").read()
# xcodebuild иногда пишет перед JSON служебные строки — отрезаем их.
start = raw.find("[")
if start < 0:
    sys.exit("showBuildSettings не вернул JSON")

entries = json.loads(raw[start:])
target = os.environ["TARGET"]

# Схема тянет за собой зависимости (виджет, App Clip) — нужен блок ровно про приложение.
match = next((e for e in entries if e.get("target") == target), None) or (entries[0] if entries else None)
if not match:
    sys.exit("showBuildSettings ничего не вернул")

settings = match["buildSettings"]
print(settings["BUILT_PRODUCTS_DIR"], settings["FULL_PRODUCT_NAME"])
PY
)"

APP_SOURCE="$PRODUCTS_DIR/$PRODUCT_NAME"
[[ -d "$APP_SOURCE" ]] || fail "Собранный бандл не найден: $APP_SOURCE"
echo "$APP_SOURCE"

log "Упаковка Payload"
mkdir -p "$STAGE/Payload"
cp -R "$APP_SOURCE" "$STAGE/Payload/"
APP="$STAGE/Payload/$PRODUCT_NAME"

# App Clip в LiveContainer не запускается и его нельзя сайдлоадить —
# внутри .ipa он только занимает место.
if [[ -d "$APP/AppClips" ]]; then
  echo "• убираем App Clip ($(du -sh "$APP/AppClips" | cut -f1))"
  rm -rf "$APP/AppClips"
fi

if [[ "$KEEP_PLUGINS" != "1" && -d "$APP/PlugIns" ]]; then
  echo "• убираем расширения (PlugIns)"
  rm -rf "$APP/PlugIns"
fi

# Остатки подписи: после CODE_SIGNING_ALLOWED=NO их быть не должно,
# но вложенные бандлы иногда приносят свои.
find "$STAGE/Payload" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
find "$STAGE/Payload" -name "embedded.mobileprovision" -type f -delete
find "$STAGE/Payload" -name ".DS_Store" -type f -delete

if [[ -n "$BUILD_NUMBER" ]]; then
  echo "• CFBundleVersion = $BUILD_NUMBER"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Info.plist"
fi

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist"; }

BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
EXECUTABLE="$(plist CFBundleExecutable)"

[[ -f "$APP/$EXECUTABLE" ]] || fail "В бандле нет исполняемого файла $EXECUTABLE"

log "Проверка бандла"
echo "Bundle ID:    $BUNDLE_ID"
echo "Версия:       $VERSION ($BUILD)"
echo "Архитектуры:  $(lipo -archs "$APP/$EXECUTABLE")"

# LiveContainer подписывает гостя сам, а чужая подпись ему только мешает.
if codesign -dv "$APP" >/dev/null 2>&1; then
  echo "Подпись:      найдена, снимаем"
  find "$STAGE/Payload" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) \
    -exec codesign --remove-signature {} + 2>/dev/null || true
  codesign --remove-signature "$APP" 2>/dev/null || true
else
  echo "Подпись:      отсутствует (как и нужно LiveContainer)"
fi

mkdir -p "$OUTPUT_DIR"
IPA_NAME="${IPA_NAME:-${SCHEME}-${VERSION}-${BUILD}-unsigned.ipa}"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
rm -f "$IPA_PATH"

log "Сборка .ipa"
(cd "$STAGE" && zip -qry "$IPA_PATH" Payload)

echo "Готово: $IPA_PATH ($(du -h "$IPA_PATH" | cut -f1))"

# Для GitHub Actions: отдаём путь и метаданные следующим шагам.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "ipa-path=$IPA_PATH"
    echo "ipa-name=$IPA_NAME"
    echo "version=$VERSION"
    echo "build=$BUILD"
    echo "bundle-id=$BUNDLE_ID"
  } >> "$GITHUB_OUTPUT"
fi
