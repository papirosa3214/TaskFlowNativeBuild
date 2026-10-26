# Ошибка компиляции меню модели

26.10.2026. При добавлении SwiftUI.Label в ChatModelMenu его generic-параметр Label перекрыл имя системного типа. Компилятор: ChatModelChoice.swift:57: type 'Label' has no member 'init'.

Generic переименован в MenuLabel; поведение и вид меню не меняются. Ошибка воспроизведена точечной проверкой типов до исправления; после правки та же проверка macOS PASS. Дополнительно настоящие ChatModelChoice.swift, ChatPromptPanel.swift и модель ChatComposerControls.swift проверены swiftc -typecheck с iPhoneOS SDK, target arm64-apple-ios18.0 — PASS. Только зависимости APIClient/RoleChat заменены минимальными интерфейсными заглушками, сетевых вызовов нет. Сторож дизайн-системы PASS. Полная сборка приложения и установка не выполнялись. Незавершённые изменения общей панели оставлены в рабочем дереве отдельно.
