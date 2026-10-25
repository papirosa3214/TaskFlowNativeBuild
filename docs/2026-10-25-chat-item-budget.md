# Editable checklist action budget
2026-10-25. Existing Server settings > Limits screen now exposes the server registry parameter chat_item_max_actions (default 10 per item). Generic editor displays the server explanation, validates integer bounds and supports existing save/reset/history. Added contextual hint and its unit test.
Server accounting is durable per item, not per model turn; see .110 docs/2026-10-25-chat-item-budget.md. Server: 65 tests passed and build passed. iOS: RED missing explanation property, GREEN 7 targeted unit tests and simulator build passed; design guard and diff check clean.
Owner requested immediate commit before screenshot verification finished. No UI tests, iPhone install, push or production restart. Setting appears on live server after deployment.
