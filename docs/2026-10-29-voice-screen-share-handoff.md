# Handoff — голос Помощника + экран iPhone

Обновлено 29.10.2026. Реализация подготовлена к проверке владельцем, открытых технических шагов перед ней нет. Полный итог и короткий сценарий: /Users/max/Проекты/TaskFlowNativeBuild/docs/2026-10-29-voice-screen-share.md.

## Состояние

- iOS основной коммит **18c733a7** уже в origin/main: ReplayKit extension, App Group, background audio, видеодорожка в тот же голосовой LiveKit-звонок, системное подтверждение, подсказка, существующая Live Activity. Завершающий коммит этой сдачи добавляет регистрацию URL-схемы taskflow и финальные документы; точный хэш — в git log.
- Последняя signed device build после URL-схемы PASS: /tmp/taskflow-screen-share-url-build.log. Собранный app содержит taskflow scheme и audio background mode. codesign app/appex=0, реальные профили App Group выданы Personal Team RUD4WAP9DF.
- Серверный исходный коммит **35d18550**, PR **https://github.com/papirosa3214/New-Todoist/pull/18**, **MERGED 53f3fc122cd0ac77c6b94cab089986df3b21352f**, все CI зелёные.
- .110 voice worker **active**, PID **1139961**, запуск **01:15:14 МСК**, регистрация **AW_5wd7e7ftCVui в 01:15:18 МСК**, NRestarts=0. video_input=True есть в рабочем коде. Pillow 13.0.0 установлена. Повторного рестарта в завершающем проходе не было.
- Перед первоначальным restart была проверка 0 активных voice rooms; backup **server/backups/pre-voice-screen-20261028-221511.db** существует. Старый unified session 16230 недоступен, проверены реальные service/log/code.
- HTTP health **200**. Deployed marker **f9221b57237a22bbc03b0093186ee95aa9bac9b9** содержит merge 53f3fc12.
- Собственный влитый серверный worktree **/home/maksim/.cache/taskflow-voice-screen-share** и локальная ветка удалены. Чужая roles/inbox-attention-tap сохранена. Сейчас другой агент имеет грязную **feature/async-subagent-call-20261029** в общей .110 копии — не переключать её, не коммитить/стэшить чужие файлы. Наш код уже выложен.

## Проверки

24 Python unit PASS, entrypoint RED→GREEN, synthetic frame encoder RED missing Pillow→GREEN. HintCenter RED→GREEN и 2 voice presentation unit PASS на macOS без симулятора. Gemini Live через штатный proxy прочитал synthetic video code 7392 голосом. xcodegen, Swift parse, diff check, дизайн-сторож и signed device build PASS. Последних исходников после успешной сборки не меняли.

## Следующее действие — проверка владельцем

Обновить приложение обычной установкой владельца → чат «Помощник» → голос → «Показать экран Помощнику» → системное «Начать трансляцию» TaskFlow, микрофон ReplayKit OFF → открыть другое приложение и продолжить говорить о конкретном видимом тексте → проверить возврат через Live Activity и остановку показа отдельно от звонка.

Физический owner scenario не проверен агентом. Не устанавливать, не запускать экран/микрофон, симулятор или UI-тесты без отдельного поручения. Live Activity не обеспечивает фон сама; используется background audio и текущий LiveKit mic. Текстовый vision других Pi-ролей не реализован.

Сохранять чужие untracked docs, build_traffic и diag-screen.png. iOS свои изменения — main + push origin main; сервер — .110 отдельная ветка/PR. Не создавать TaskFlow карточки/роли. Не менять RoleReplyMarkdown.readableText.
