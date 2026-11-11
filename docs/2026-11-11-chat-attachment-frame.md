# Картинка-вложение: фиксированная рамка

LOCK-CHAT-ATTACH-FRAME-20261111.

Пока грузится — 140 pt, после — `.fit` без потолка. `UITableView.automaticDimension` меняет высоту строки, лента дёргается.

Передача не менялась: id → `downloadAttachment`.

Показ: всегда `220×140`, картинка `.fit` внутрь, `.clipped()`.

Проверка: `python3 Tools/test_chat_attachment_frame.py`. Сборка и iPhone — не запускались.
