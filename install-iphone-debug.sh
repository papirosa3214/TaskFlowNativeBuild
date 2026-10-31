#!/bin/bash
# ═══════════ Отладочная установка TaskFlow на iPhone (DEBUG) ═══════════
#
# ⚠️ Это НЕ рабочий установщик. Рабочий install-iphone.sh всегда ставит
#    Release: его вызывает кнопка «Задачник» в пульте .110 через службу
#    InfraPanelInstaller на Маке, и Debug там жрёт CPU (владелец 29.10.2026).
#    Этот файл ничего в нём не меняет — он лишь зовёт его с CONFIG=Debug.
#
# Зачем: в Debug-сборке лента сама пишет трейс геометрии
# (ApplicationSupport/ChatScrollDiagnostics/session-*.json) — геометрия без
# текста сообщений и без ID. Это шаг 1 разбора «почему лента прыгает»:
# сначала снять данные, потом что-то менять (31.10.2026).
#
# Как пользоваться:
#   1) ./install-iphone-debug.sh          — поставить Debug и включить трейс
#   2) на телефоне повторить прыжок: открыть чат роли, дождаться ответа,
#      печатать в поле пока идёт ответ, отлистать вверх (2 минуты)
#   3) забрать файлы:
#        xcrun devicectl device copy from --device 00008150-001545400144401C \
#          --domain-type appDataContainer \
#          --domain-identifier com.maksim.taskflow.native \
#          --source ChatScrollDiagnostics --destination /tmp/trace
#
# ВАЖНО: Debug на телефоне тяжелее по CPU. После замера верни релиз:
#   ./install-iphone.sh

set -euo pipefail
cd "$(dirname "$0")"

# Служба на Маке запускает скрипты без PATH пользователя — xcodegen в homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEVICE_ID="00008150-001545400144401C"
BUNDLE_ID="com.maksim.taskflow.native"

printf '\n\033[1m▸ Ставлю DEBUG-сборку (только ради трейса ленты)\033[0m\n'
CONFIG=Debug ./install-iphone.sh

printf '\n\033[1m▸ Перезапускаю с записью трейса\033[0m\n'
# Перезапуск нужен, чтобы приложение поднялось с нужным окружением.
xcrun devicectl device process terminate --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
# CHAT_SCROLL_TRACE=1 — включает запись трейса и в Release-сборке, если её
# потом соберут с этим флагом. В Debug запись и так включена.
xcrun devicectl device process launch --device "$DEVICE_ID" \
  -e '{"CHAT_SCROLL_TRACE":"1"}' "$BUNDLE_ID"

cat <<'TXT'

Готово. Теперь на телефоне:
  1) открой чат роли и дождись ответа;
  2) печатай в поле, пока идёт ответ (клавиатура открыта);
  3) отлистай ленту вверх и вернись вниз.

После этого скажи «готово» — я заберу файлы и назову причину.

Не забудь потом вернуть релизную сборку:
  ./install-iphone.sh
TXT
