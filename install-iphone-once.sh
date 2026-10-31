#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  Разовый локальный прогон: собрать TaskFlow под iPhone и поставить.
#
#  Ничего не коммитит, не пушит и не меняет git-историю. Единственное,
#  что перезаписывается, — сгенерированный TaskFlow.xcodeproj (он всё
#  равно собирается из project.yml) и папка build_device.
#
#  Можно удалить после проверки.
#
#  Запуск:   ./install-iphone-once.sh
#  Debug:    CONFIG=Debug ./install-iphone-once.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")"

# Служба/SSH не несут PATH пользователя: xcodegen лежит в homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEVICE_ID="${DEVICE_ID:-00008150-001545400144401C}"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="${BUILD_DIR:-build_device}"

шаг() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

шаг "Пересобираю проект из project.yml"
xcodegen generate

шаг "Собираю $CONFIG под устройство $DEVICE_ID"
xcodebuild \
  -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -configuration "$CONFIG" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  build

APP="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/TaskFlow.app"
if [ ! -d "$APP" ]; then
  printf '\n\033[31m✗ Сборка не найдена: %s\033[0m\n' "$APP"
  exit 1
fi

шаг "Ставлю на iPhone"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

шаг "Запускаю"
if xcrun devicectl device process launch --device "$DEVICE_ID" com.maksim.taskflow.native; then
  printf '\n\033[32m✓ Готово — TaskFlow собран и запущен на телефоне.\033[0m\n'
else
  printf '\n\033[33m! Установлено, но не запустилось: разблокируй телефон и открой «Задачи» руками.\033[0m\n'
fi
