#!/usr/bin/env bash
# Иконки сервисов Composio: SVG → серый силуэт → PNG в Resources/ComposioIcons.
#
# Шаги:
#   1. каталог Composio с сервера (.110) — список сервисов, их названия,
#      русские описания и адреса логотипов;
#   2. сами SVG по адресам логотипов;
#   3. рендер в серый (`render.swift`, WebKit рисует SVG);
#   4. ужимание (`optimize.py`, если есть PIL).
#
# Логотипы Composio — SVG, iOS их не рисует: без этого шага в списке
# подключений вместо иконок был generic-значок «link».
#
# Запуск: bash Tools/composio_icons/build.sh [каталог SVG]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

work="${1:-/tmp/composio_icons}"
mkdir -p "$work/svg"

host="${COMPOSIO_HOST:-192.168.1.110}"
remote_catalog="/tmp/composio_catalog.json"

echo "1/4 каталог Composio с $host"
ssh "maksim@$host" 'cd ~/Проекты/New-Todoist/server && cat > /tmp/dump_catalog.sh <<"EOS"
set -e
out=/tmp/composio_catalog.json
echo "[]" > $out
cursor=""
for i in $(seq 1 40); do
  if [ -n "$cursor" ]; then export TASKFLOW_COMPOSIO_CURSOR="$cursor"; else unset TASKFLOW_COMPOSIO_CURSOR || true; fi
  TASKFLOW_COMPOSIO_USER_ID=taskflow:u1 \
  TASKFLOW_COMPOSIO_OPTIONS='"'"'{"mcp":true,"manageConnections":{"enable":false},"sandbox":{"enable":true}}'"'"' \
  timeout 120 python3 scripts/composio_vault.py ~/.claude/vault-run.py API_COMPOSIO node scripts/composio_mcp.mjs --catalog > /tmp/page.json
  python3 - <<"PY"
import json
cat=json.load(open("/tmp/composio_catalog.json"))
cat.extend(json.load(open("/tmp/page.json")).get("items",[]))
json.dump(cat, open("/tmp/composio_catalog.json","w"))
PY
  cursor=$(python3 -c "import json;print(json.load(open(\"/tmp/page.json\"))[\"cursor\"] or \"\")")
  [ -z "$cursor" ] && break
done
python3 -c "
import json;c=json.load(open(\"/tmp/composio_catalog.json\"));print(\"сервисов:\",len(c))"
EOS
bash /tmp/dump_catalog.sh' | tail -2

scp -q "maksim@$host:$remote_catalog" "$work/catalog.json"

echo "2/4 логотипы (SVG)"
python3 - "$work/catalog.json" "$work/urls.txt" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as handle:
    for item in catalog:
        handle.write(f"{item['slug']} {item['logo']}\n")
print("сервисов:", len(catalog))
PY

cat > "$work/fetch.sh" <<'EOS'
#!/bin/bash
slug="$1"; url="$2"
out="/tmp/composio_icons/svg/$slug.svg"
[ -s "$out" ] && exit 0
curl -s -L --max-time 20 "$url" -o "$out"
EOS
chmod +x "$work/fetch.sh"
awk '{print $1, $2}' "$work/urls.txt" | xargs -P 16 -n 2 "$work/fetch.sh"

echo "3/4 рендер серым силуэтом"
cut -d' ' -f1 "$work/urls.txt" > "$work/slugs.txt"
swift Tools/composio_icons/render.swift "$work/svg" Resources/ComposioIcons "$work/slugs.txt" | tail -1

echo "4/4 ужимание"
/usr/bin/python3 Tools/composio_icons/optimize.py Resources/ComposioIcons || true

echo "готово: $(ls Resources/ComposioIcons | wc -l | tr -d ' ') иконок"
