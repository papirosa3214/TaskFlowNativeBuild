# Markdown Document Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give stored Markdown documents a read-only preview with the same clear hierarchy and spacing as JSON reports, while keeping editing, Markdown source, and downloaded artifact files unchanged.

**Architecture:** Reuse the existing `MarkdownParser` and its `NoteBlock` AST, then feed common content blocks to shared SwiftUI presentation components used by both Markdown documents and JSON output. JSON-only blocks such as charts, status, progress, diagrams, and handoffs remain typed JSON views. The first prototype adds an explicit preview action for a saved task document; the existing note editor and persisted data remain unchanged.

**Tech Stack:** SwiftUI, existing `MarkdownParser`/`NoteBlock`/`RichRun`, TaskFlow DesignSystem, XcodeBuildMCP.

**Spec:** `docs/2026-10-17-structured-role-output-contract.md`

## Global Constraints

- Keep existing Markdown source and TipTap JSON storage as-is; do not save a converted copy.
- Do not transform, rename, or replace downloaded artifact files.
- Keep the editable note screen and role prompts out of this prototype; preview is read-only and separate.
- The renderer owns typography, spacing, colors, table layout, and accessibility; model or Markdown content carries no styling values.
- Use the light verification mode from `AGENT-CYCLE.md`; run the focused check asynchronously in the background.

## Review Focus

- Inline emphasis, code, and links remain visible after the Markdown AST is adapted — test mixed inline marks.
- A table cell can wrap without covering the next row — test a long cell followed by another row.
- Unsupported or malformed Markdown is not silently dropped — test an unclosed code fence and unsupported syntax fallback.
- JSON-only blocks keep their current behavior — the existing typed output preview must still render.
- Export and stored source remain unchanged — verify the export path still receives the original Markdown document or original artifact file.

---

## Storage findings that constrain the UI work

- Each new task receives an `artifact_folder_id` under the project's `journal_folders` documentation tree. Older tasks get a task folder on their first document write.
- `saveRoleResultReport` writes its Markdown report as TipTap JSON into that task folder and links it to the task event/document list. The task outcome summary is intentionally written at the project documentation level.
- Plan artifacts are also stored as versioned JSON records in `subtask_artifact_versions`; `note_id` is optional. An artifact reference or file path is not itself proof that a file was copied into the task folder.
- The KB triage watcher counts only notes with `kb_temp_category` set and no permanent `kb_category`. It runs at a threshold; the helper categorizes notes and marks likely junk, but the watcher instructions explicitly say not to delete it.
- The normal notes-create route labels a note created under a task artifact folder. Direct report writers such as `saveRoleResultReport` insert notes without going through that route, so they may not enter the current triage count. “Every artifact is stored and triaged” is therefore not guaranteed by the current path.

Storage/tagging completeness is a separate server change. This UI prototype reads the document that already exists and does not change its save, classify, or delete lifecycle.

## File map

- Create `Sources/Features/Markdown/MarkdownDocumentRenderer.swift`: Markdown-to-display adapter, reusable SwiftUI blocks, and read-only document preview that loads Markdown from the existing notes API.
- Modify `Sources/Features/Chat/ChatStructuredOutputView.swift`: delegate shared content blocks to the reusable renderer; keep JSON-specific widgets here.
- Modify `Sources/Features/Task/Detail/TaskOutcomeSection.swift`: add an explicit «Предпросмотр» action for a stored task document; preserve the current edit action and exports.
- Modify `Sources/Features/Task/TaskFormScreen.swift`: present and dismiss the read-only preview sheet.
- Modify `Sources/App/TaskFlowApp.swift` (DEBUG preview only): open a deterministic Markdown fixture for UI acceptance without a live artifact.
- Create `UITests/MarkdownDocumentRendererUITests.swift`: one focused preview scenario with a long table cell and mixed formatting; save its screenshot attachment.
- Create `docs/2026-10-17-markdown-document-rendering.md`: implementation result and verification evidence.

## Implementation tasks

### Task 1: Adapt existing Markdown blocks to a reusable display model

**Files:**
- Create: `Sources/Features/Markdown/MarkdownDocumentRenderer.swift`
- Test: `Tests/MarkdownDocumentRendererTests.swift`

**Interfaces:**
- Produce `MarkdownDocumentAdapter.blocks(from markdown: String) -> [DocumentContentBlock]`.
- `DocumentContentBlock` represents paragraph runs, heading level/runs, list item kind/depth/runs, quote runs, code text/language, table rows, and horizontal rule.
- Consume `MarkdownParser.parse(_:)`; preserve `RichRun` values instead of flattening inline marks to plain text.

- [ ] Add `MarkdownDocumentRendererTests.testAdapterPreservesDocumentStructureAndInlineMarks`; assert heading level, nested/list kind, bold/link runs, table cell count, and code language.
- [ ] Add malformed-fence assertion; unclosed code must remain visible as text rather than disappear.
- [ ] Run only `MarkdownDocumentRendererTests` and confirm the adapter behavior.

### Task 2: Share presentation for Markdown and JSON content blocks

**Files:**
- Modify: `Sources/Features/Markdown/MarkdownDocumentRenderer.swift`
- Modify: `Sources/Features/Chat/ChatStructuredOutputView.swift`

**Interfaces:**
- `MarkdownDocumentRenderer(markdown: String)` parses once and renders the adapted blocks.
- `StructuredDocumentBlockView(block: DocumentContentBlock)` owns typography, hierarchy, spacing, inline marks, and tables.
- `ChatStructuredOutputView` maps JSON `text`, `heading`, `list`, and `table` blocks into the same `DocumentContentBlock` cases. Its status, progress, chart, diagram, report-card, and handoff views remain JSON-specific.

- [ ] Render a representative Markdown document through the shared view: title, paragraph with bold/link, ordered and unordered lists, quote, code, and a three-column table.
- [ ] Keep unsupported Markdown visible through a plain-text fallback with no data loss.
- [ ] Confirm the existing JSON v1 preview still uses the shared components for its simple content blocks.

### Task 3: Connect a read-only preview for a stored task document

**Files:**
- Modify: `Sources/Features/Markdown/MarkdownDocumentRenderer.swift`
- Modify: `Sources/Features/Task/Detail/TaskOutcomeSection.swift`
- Modify: `Sources/Features/Task/TaskFormScreen.swift`

- [ ] Add «Предпросмотр» to the stored-document row actions and present `MarkdownDocumentPreviewScreen(noteID:title:)`.
- [ ] Load through `APIClient().note(id: noteID, format: "markdown")`; render in memory only.
- [ ] Keep the existing note-editor action, task-folder storage, and «Сохранить на телефон» export unchanged.

### Task 4: One focused visual acceptance run

**Files:**
- Modify: `Sources/App/TaskFlowApp.swift` (DEBUG fixture route only)
- Create: `UITests/MarkdownDocumentRendererUITests.swift`
- Create: `docs/2026-10-17-markdown-document-rendering.md`

- [ ] Add `MarkdownDocumentPreviewScreen(previewMarkdown:title:)` under `#if DEBUG` and a `TASKFLOW_MARKDOWN_DOCUMENT_PREVIEW=1` app entry branch with heading, bold/link text, lists, quote, code, and a long table cell.
- [ ] Add one UI test that opens the fixture preview and checks the heading, table, and following row accessibility frames.
- [ ] Capture one `XCTAttachment(screenshot:)` and inspect the Markdown and JSON examples side by side.
- [ ] Run the focused simulator test asynchronously in the background; stop after one passing run, and record any unrelated test/build blocker without repairing outside scope.
- [ ] Record whether the first render matches the JSON report hierarchy; do not extend to the editable notes screen until the owner approves the prototype.

## Follow-up outside this prototype

Audit the server writers that create task-folder documents and plan artifacts. Ensure each intended document gets a task-source link and is admitted to the KB triage queue. Confirm what “garbage” means in the current workflow: today it is marked and retained, not deleted. Scope this separately before changing the production server or the triage policy.
