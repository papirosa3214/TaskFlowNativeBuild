#!/bin/bash
# ═══════════ Накатить TaskFlow на iPhone ═══════════
#
# Нужно примерно раз в неделю: бесплатная подпись Apple живёт 7 дней, после
# чего приложение перестаёт запускаться.
#
# Этот файл — дословно та последовательность, которой владелец ставит задачник
# руками (15.09.2026). Он же вызывается кнопкой «Задачник» в пульте .110:
# панель просит службу InfraPanelInstaller на Маке, та запускает этот скрипт.
# Служба не может выполнить произвольную команду — только то, что здесь.
#
# Рядом у ГеоФото лежит install-iphone.sh, который ищет телефон сам. Здесь
# устройство названо явно, как в команде владельца; если понадобится ставить
# на другой телефон — менять эту одну строку.

set -euo pipefail
cd "$(dirname "$0")"

# Служба на Маке запускает скрипт без PATH пользователя — xcodegen лежит в
# homebrew, и без этого сборка падает «xcodegen: command not found».
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEVICE_ID="00008150-001545400144401C"

шаг() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

шаг "Пересобираю проект из project.yml"
xcodegen generate

шаг "Собираю и подписываю"
# `-allowProvisioningUpdates` — чтобы xcodebuild мог САМ перевыпустить профиль
# бесплатной подписи. Без флага, когда профиль истёк, сборка падает на
# «No profiles for 'com.maksim.taskflow.native' were found… Automatic signing is
# disabled and unable to generate a profile», хотя код собирается (проверено
# 22.09.2026 — владелец ловил именно это). В Xcode профиль обновляется молча,
# из командной строки для этого нужно разрешение явно; иначе пришлось бы каждый
# раз открывать Xcode руками.
xcodebuild \
  -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build_device \
  -allowProvisioningUpdates \
  build

шаг "Ставлю на телефон"
xcrun devicectl device install app --device "$DEVICE_ID" \
  build_device/Build/Products/Debug-iphoneos/TaskFlow.app

шаг "Запускаю на телефоне"
# Телефон должен быть разблокирован и доверен: иначе запуск падает
# «FBSOpenApplicationErrorDomain error 7» (устройство Locked).
if xcrun devicectl device process launch --device "$DEVICE_ID" com.maksim.taskflow.native; then
  printf '\n\033[32m✓ Готово — задачник на телефоне и запущен.\033[0m\n'
else
  printf '\n\033[33m! Установлено, но не запустилось: разблокируй телефон и открой «Задачник» руками.\033[0m\n'
fi
printf 'Следующий раз понадобится примерно через неделю.\n'
