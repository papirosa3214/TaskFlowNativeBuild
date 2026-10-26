# Agent prompt settings implementation plan

Goal: three clear editing surfaces using existing canonical sources.
Architecture: Team → common role.system; agent → personality (existing behavior editor), personal role.prompt (existing versioned instruction editor). Reuse API, history and conflict handling. Existing technical context remains under advanced settings.
Spec: owner approval 26.10.2026 and server docs/2026-10-26-universal-owner-assistant.md.

Constraints: canonical Mac checkout only; server changes over SSH; no simulator, UI tests, device installation or push. Preserve unrelated staged files.

- [x] Add a failing hint navigation unit test; run the real hint engine on macOS.
- [x] Add common instructions entry to Team and two named agent forms, reusing existing editors. Keep create-role prompt input.
- [x] Add matching hints, run unit GREEN, parse Swift and design guard.
- [x] Replace secretary personality and personal instructions through existing versioned domain service; retain permissions, history and voice identity.
- [x] Run focused existing server tests, inspect actual assembled assistant chat/voice instruction, save report and commit only own files.

Review focus: global instructions affect all agents; persona/personal edits affect one role; drafts survive stale versions; loading failures expose retry; creating a role still accepts its initial instructions.
