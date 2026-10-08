# Connected role HTML panels — 2026-10-08

Role HTML buttons can call `await TaskFlow.runCommand(command)` directly from their click handler. Native iOS confirmation shows the exact Bash command for server .110. The Promise returns stdout, stderr, exitCode, outcome, durationSeconds and requestId; cancellation/errors reject it. Owner credentials never enter HTML.

## Verification

2 unit tests and 2 XCUITests passed. The HTML button ran `printf 'Panel Live OK'` on the live server and displayed its output and exit code. Cancellation and denied owner permission were verified. Result bundle: /tmp/html-panel-tests2.xcresult. Screenshot: docs/2026-10-08-html-panel-actions/.

Eight role prompt files now teach the SDK. Migration 122 updates existing custom prompts. Isolated server build and migration rehearsal passed. Live service restarted with no queued/running jobs; health and SQLite integrity passed, active custom prompt contains the contract. Main checkout build still reports the pre-existing notesFolders.ts:43 type error. An additional rehearsal using the system Node crashed; isolated rehearsal passed and the live service remains healthy.

## Usage and limits

Useful buttons: service health, queue status, log inspection, agreed maintenance scripts. Commands execute on .110, not on the iPhone. Execution requires owner access and native confirmation. Old HTML panels must be updated/regenerated to call the SDK. Output lives in the current WebView; the server command journal persists separately. Interactive verification used the simulator with the live server; physical-device installation is reported separately.
