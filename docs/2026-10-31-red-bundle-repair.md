# Красный бандл `TaskFlowTests` — починка (31.10.2026)

Фича `m1-fix-red-xctest-bundle`, VAL-INFRA-014. База миссии `737f86e6` + `f03aaad6`
(импорты) + `c9fd42d9` (пути хостовых скриптов).

## Замер «до»

```
xcodebuild … test -only-testing:TaskFlowTests
→ Executed 1001 tests, with 40 failures (5 unexpected)   ** TEST FAILED **
```

40 — это упавшие **утверждения**; тест-кейсов красных 26, в 11 файлах. Замер
пройден на простоев машине, повторяем (флаки нет).

## Решение по каждому красному кейсу

| Файл | Кейс | Что устарело | Правка |
|---|---|---|---|
| `Tests/LocalDbSyncTests.swift` | 5 кейсов | **тест**: фикстуры не по контракту моделей | фикстуры: `created_by` в чатах, `title`+`status` в задачах |
| `Tests/RoleReplyChartTests.swift` | `testBothPathsDrawChartByOneComponent`, `testChartColorIsShared` | **тест**: пути к исходникам (переезд `8212bc89`) | пути → `Sources/ChatComponents/Output/…`, `Sources/ChatComponents/Widgets/…`, `Sources/Features/Roles/RoleChartBlock.swift` |
| `Tests/RoleReplyRenderTests.swift` | `testRoleTextPlacesUseCommonRenderer`, `testOutcomeRowPreviewGoesThroughCommonRenderer` | **тест**: пути + контракт отрисовки | пути → `Features/Notifications/`, `Features/Roles/`, `TaskCardContent.swift`; общий рендер — `RoleReplyMarkdown` **или** обёртка `TaskRoleReply`; превью — по контракту 29.10.2026 |
| `Tests/UIStyleGateTests.swift` | `testConnectActionsAreGreyNotRed` | **тест**: кнопка «Подключить аккаунт» удалена продуктом (29.10.2026, тумблер) | список подключений — по тому, что есть; экран Composio — guard «у каждой кнопки явный `variant:`» |
| `Tests/UIStyleGateTests.swift` | `testSaveConfirmationStaysPrimary` | **тест**: кнопка сохранения в профиле серая с 22.10.2026 (поручение владельца) | путь → `EditProfileScreen.swift`, ожидание → `.secondary`, кейс переименован в `testSaveConfirmationUsesAgreedVariant` |
| `Tests/UIStyleGateTests.swift` | `testMachinesLoadFailureUsesSharedErrorAndButton` | **тест**: путь к исходнику | путь → `Sources/Features/Settings/RemoteMachinesScreen.swift` |
| `Tests/AppDiagnosticsTests.swift` | `testJournalIsBoundedAndReportContainsOnlyCounters` | **тест**: отчёт переписан 18.10.2026 (`4bfa858f`) | ожидание → `Пробуждения очереди: всего 100` |
| `Tests/HintCenterTests.swift` | `testOwnMessageCopyHintCompletes` | **тест**: текст подсказки переписан 26.10.2026 (долгое нажатие вместо иконки) | ожидания → новая формулировка |
| `Tests/HintCenterTests.swift` | `testWebhookHintExplainsGenericReceiverAndOptionalCodexBranch` | **тест**: в тексте сценария «Codex не обязателен» (без «здесь») — так с 20.10.2026 | ожидание → фактическая формулировка |
| `Tests/RealtimeEnergyTests.swift` | `testOnlyAffectedCardWakesAndReconnectRestoresAllCards` | **тест**: с 27.10.2026 реконнект сам по себе карточки не будит (`3d1d1c33`) | ожидания по новому контракту + проверка дельты (`recordCatchUp`) |
| `Tests/RoleChatComposerTests.swift` | `testDeepResearchRequiresResearcherAndKeepsBackwardCompatibility` | **тест**: режим «Цель» есть с 20.10.2026 (`e03d0e87`) | ожидания → `[.work, .plan, .goal]` / `[.work, .plan, .goal, .deepResearch]` |
| `Tests/RoleChatLiveTurnTests.swift` | 6 кейсов (`testRevealedActionsSurviveRemovalFromSnapshot`, `testFinalAnswerDrainsSmoothlyWithinCompletionWindow`, `testCompletedLongReplyDrainsWithinTwoSeconds`, `testRepeatedCompletionDoesNotPostponeDeadline`, `testPacerShowsStepsAfterPreviousTextAndResetsChangedText`, `testLongReplyCatchesUpWithoutArtificialReadingDelay`) | **тест**: с 17.10.2026 срок досыпа считается по остатку символов (`1f58d8d7`), с 30.10.2026 показанный живой ход не укорачивается (`4d13c630`) | ожидания по действующему контракту; `testCompletedLongReplyDrainsWithinTwoSeconds` переименован в `testCompletedLongReplyDrainsWithinDeclaredBudget` |
| `Tests/ServiceTicketPresentationTests.swift` | `test_truncatedMessageIsMarked` | **КОД**: `markTruncated` не убирает хвостовые пробелы перед дописыванием | правка `Sources/Features/Notifications/ServiceTicketPresentation.swift` — RED → GREEN |
| `Tests/VoiceRecordingWaveformTests.swift` | `testBarsKeepTheirLevelsWhileRecorderDropsOldOnes`, `testLiveWaveIsSymmetricAndHoldsSustainedSound` | **тест**: 20.10.2026 — 3 замера на столбик (`e90bab21`) и новые пороги (`55a667a4`) | ожидания по действующим константам; проверка живой волны переведена на живой путь (`amplitude` → `normalizedHistory` → `patterned`) |

## Изменённые файлы под `Sources/`

Один файл — и только потому, что тест доказывает неверность поведения:

- `Sources/Features/Notifications/ServiceTicketPresentation.swift` — `markTruncated(_:)`:
  хвостовые пробелы убираются перед дописыванием «подробности не пришли».
  RED: `XCTAssertEqual failed: ("проверка не прошла:    подробности не пришли") is not
  equal to ("проверка не прошла: подробности не пришли")` → GREEN после правки.

## Что найдено, но не правилось (вне фичи)

- `Sources/Core/Store/LocalStore.swift` (`chats()`, `tasks()`) декодирует сырой
  `payload_json` моделью через `try?`: запись без обязательного поля молча
  исчезает при чтении. Это надёжность production-кода upstream, а не фикстура
  теста — вынесено владельцу (см. `AGENTS.md`, «Отложенные находки»).
- `RoleReplyMarkdown.preview(of:)` и `previewSegments(of:key:)` больше не
  вызываются из `Sources/` — остались только в тестах.
- `VoiceRecordingWaveformView`: `bars`, `smoothed`, `normalized(level:peak:)`,
  `height(level:maximum:)`, `barHeight` не имеют вызовов в `Sources/`; живая
  волна идёт через `amplitude` → `normalizedHistory` → `patterned`. Мёртвый код —
  к milestone «Зачистка».
- `RoleReplyRenderTests.testNoChartMarksOutsideSharedComponent` проверяет пути
  относительно `Sources/`, но читает их от корня репозитория — ни один файл не
  открывается, проверка проходит вхолостую. Починка вскроет второй рисунок
  графика в `Sources/Features/Activity/AIUsageScreen.swift` — это отдельная
  находка, не эта фича.
- Комментарий в `Sources/Core/Models/RoleChat.swift` («остаток дописывается за
  `completionDrain`») устарел: `completionDrain` — только пол срока.
