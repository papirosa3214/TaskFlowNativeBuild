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

# Ставить можно только из основной папки. У каждой рабочей копии роли
# (.worktrees/<id>) свой экземпляр этого скрипта и своя ветка — запуск
# оттуда ставил на телефон чужую сборку (владелец 10.11.2026: «или вы все
# со своих копий ставите мне приложение»).
case "$(pwd -P)" in
  */.worktrees/*)
    echo "Это рабочая копия роли ($(pwd -P)). Сборка на телефон — только из ~/Проекты/TaskFlowNativeBuild."
    exit 1
    ;;
esac

# Служба на Маке запускает скрипт без PATH пользователя — xcodegen лежит в
# homebrew, и без этого сборка падает «xcodegen: command not found».
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEVICE_ID="00008150-001545400144401C"

# Конфигурация сборки — по умолчанию Release, то есть оптимизированная.
#
# Почему Release (владелец 29.10.2026): на телефоне стояла Debug-сборка, и
# TaskFlow ел 50–100% CPU — профиль iPhone показал 13 срабатываний за 11 дней,
# всегда во фронте. В Debug нет оптимизации Swift, а SwiftUI в Debug тяжелее
# в разы: даже разбор JSON (Foundation собран заранее и одинаков) стоит
# одинаково, а вот отрисовка и собственная логика — заметно дороже.
#
# Debug-сборка нужна только для отладки. Взять её можно так:
#   CONFIG=Debug ./install-iphone.sh
CONFIGURATION="${CONFIG:-Release}"

шаг() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

шаг "Забираю свежий main с GitHub"
# Правки iOS вливаются через PR на GitHub (28.10.2026) — папка на маке сама
# не обновляется. Только перемотка вперёд: чужие локальные коммиты не трогаем.
if [ "$(git branch --show-current)" != "main" ]; then
  git switch main || { echo "Не могу перейти на main: в папке незакоммиченные правки агента. Сборка остановлена."; exit 1; }
fi
git pull --ff-only github main || { echo "main на маке разошёлся с GitHub — нужен агент. Сборка остановлена."; exit 1; }
# Что именно собирается — одной строкой, чтобы «каждый раз разное поведение»
# не приходилось угадывать (владелец 10.11.2026). Сборка идёт из РАБОЧЕГО дерева,
# а не из GitHub: локальные неопубликованные коммиты и правки вне коммита
# попадают в приложение.
SHA="$(git rev-parse --short HEAD)"
git log -1 --format='Версия: %h %s'
AHEAD="$(git rev-list --count github/main..HEAD 2>/dev/null || echo 0)"
if [ "$AHEAD" != "0" ]; then
  printf '\033[33m! В дереве %s коммит(ов) сверх зеркала: в GitHub их ещё нет.\033[0m\n' "$AHEAD"
fi
DIRTY="$(git status --porcelain -- Sources Resources project.yml 2>/dev/null | wc -l | tr -d ' ')"
if [ "$DIRTY" != "0" ]; then
  printf '\033[33m! Правок вне коммита в коде: %s. Сборка НЕ равна коммиту %s:\033[0m\n' "$DIRTY" "$SHA"
  git status --porcelain -- Sources Resources project.yml | head -8 | sed 's/^/    /'
fi
printf 'Источник кода: зеркало github (%s). Приложение ставится из этого дерева.\n' "$(git log -1 --format=%h github/main)" 

шаг "Пересобираю проект из project.yml"
# --use-cache: проект перегенерируется, только если project.yml изменился.
# Иначе Xcode каждый раз заново переоценивал проект, и сборка грела Мак
# (владелец 12.11.2026: «с нуля очень сильно грузятся, Мак кипяток»).
xcodegen generate --use-cache

шаг "Собираю и подписываю ($CONFIGURATION)"
# `-allowProvisioningUpdates` — чтобы xcodebuild мог САМ перевыпустить профиль
# бесплатной подписи. Без флага, когда профиль истёк, сборка падает на
# «No profiles for 'com.maksim.taskflow.native' were found… Automatic signing is
# disabled and unable to generate a profile», хотя код собирается (проверено
# 22.09.2026 — владелец ловил именно это). В Xcode профиль обновляется молча,
# из командной строки для этого нужно разрешение явно; иначе пришлось бы каждый
# раз открывать Xcode руками.
#
# `-configuration Release` обязателен: без него xcodebuild берёт конфигурацию
# схемы, а в схеме TaskFlow стоит `run: config: Debug` — отсюда и тянулась
# неоптимизированная сборка.
xcodebuild \
  -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build_device \
  -allowProvisioningUpdates \
  build

APP="build_device/Build/Products/$CONFIGURATION-iphoneos/TaskFlow.app"
if [ ! -d "$APP" ]; then
  printf '\n\033[31m✗ Сборка не найдена: %s\033[0m\n' "$APP"
  exit 1
fi

шаг "Ставлю на телефон"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

шаг "Запускаю на телефоне"
# Телефон должен быть разблокирован и доверен: иначе запуск падает
# «FBSOpenApplicationErrorDomain error 7» (устройство Locked).
if xcrun devicectl device process launch --device "$DEVICE_ID" com.maksim.taskflow.native; then
  printf '\n\033[32m✓ Готово — задачник на телефоне и запущен.\033[0m\n'
else
  printf '\n\033[33m! Установлено, но не запустилось: разблокируй телефон и открой «Задачник» руками.\033[0m\n'
fi
printf 'Следующий раз понадобится примерно через неделю.\n'
