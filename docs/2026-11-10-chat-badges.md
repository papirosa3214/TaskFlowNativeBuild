# Ярлычки типов файлов в чате — 10.11.2026

## Результат

Ссылка на файл показывается ярлычком типа на своём цвете — как в макете
владельца `~/.hermes/cache/scratch/envelope-badges-preview.html` (10.11.2026):

| В ответе | Что видно |
| --- | --- |
| `Sources/App/App.swift:12` | ярлычок **SW** оранжевым + `App.swift:12` |
| `server/tools/run.py` | **PY** синим + `run.py` |
| `src/lib/roleContractV1.ts` | **TS** голубым + `roleContractV1.ts` |
| `package.json` | **JSON** серым + `package.json` |
| `docs/AGENT-CYCLE.md` | **MD** синеватым |
| `/tmp/отчёт-42.pdf` | **PDF** коричневым |
| `~/Desktop/screen.png` | **IMG** фиолетовым |
| `~/Screen/demo.mp4` | **MP4** жёлтым |
| `config/settings.yaml` | **YAML** серым (неизвестное расширение — свои буквы) |

У внешних ссылок остаются иконки хостов (GitHub, GitLab, Bitbucket, Forgejo,
Gitcafe, Azure DevOps, Cursor Origin) — ярлычок только у файлов.

## Что сделано

1. `ChatLinkPresentation.Badge` + `Tint` + `badgesByExtension`:
   таблица расширений (py, swift, ts/tsx, js/jsx, json, md, sql, sh/zsh/bash,
   html, css/scss, go, pdf, png/jpg/gif/webp/heic, mp4/mov/m4v) и правило для
   неизвестных — первые четыре знака (`yaml` → `YAML`).
2. Без каталога файлом считается только имя с известным расширением
   (`roleContractV1.ts`): иначе любое слово с точкой стало бы «файлом».
3. `Sources/Chat/Feed/ChatBadgePalette.swift` — палитра из макета
   (светлая/тёмная тема), подложка — тот же цвет в 16 %.
4. `RoleReplyMarkdown.badgeText` и его подключение в `readableText` и в
   `MarkdownDocumentRenderer`: перед подписью файла — ярлычок, иначе иконка.

## Проверки

- `Tools/test_chat_link_presentation.py`: RED (поля `badge` нет — тесты не
  компилируются) → **GREEN 23/23**; новые проверки — SW/PY/TS/JSON/MD/PDF/IMG/
  MP4, неизвестное расширение, у внешней ссылки ярлычка нет.
- `xcodegen generate`; сборка `-destination 'generic/platform=iOS'` —
  **BUILD SUCCEEDED**.
- Сторож дизайн-системы — см. отчёт коммита.

## Ограничения

- Ярлычок — прогон текста с подложкой: скругления и настоящей «пилюли»
  внутри абзаца SwiftUI не рисует. Смягчено тонкими пробелами внутри прогона,
  чтобы подложка не липла к соседним буквам. Настоящая пилюля — только
  отдельной вью, то есть переезд компонента ответа на UIKit-текст (30+ мест).
- Строки «Источники» из макета (имя + хост отдельными строками со значком)
  не делались: это новый блок ответа, его должен готовить сервер.
- На живом ответе вид не проверен: симулятор и телефон не запускались,
  принимает владелец.
