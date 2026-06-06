# AgentDock V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the user-facing app to AgentDock, add CLI control, make Slock agent names read-only, and replace the simple storage snapshot with a technical treemap-based storage analyzer and cleanup review flow.

**Architecture:** Keep `StatusMenusCore` as the shared logic layer for both GUI and CLI. Add a new `agentdock` SwiftPM executable target that calls core services directly. Keep destructive cleanup guarded by review state and move-to-Trash behavior.

**Tech Stack:** SwiftPM, SwiftUI, AppKit, Foundation, macOS FileManager APIs.

---

## File Map

- Modify `Package.swift`: add the `agentdock` executable product/target.
- Modify `Sources/StatusMenusCore/Services/StorageService.swift`: add storage tree analysis, cleanup candidates, and safe trash support.
- Modify `Tests/StatusMenusCoreChecks/main.swift`: add storage analysis checks and update AgentDock menu summary expectations.
- Create `Sources/AgentDockCLI/main.swift`: implement `agentdock` command routing.
- Modify `Sources/StatusMenus/Modules/Storage/StorageView.swift`: replace the simple folder list with V2 operations deck, treemap, ranked table, and cleanup review.
- Modify `Sources/StatusMenus/Modules/Slock/SlockAgentsView.swift`: disable name editing while keeping local description and memory editing.
- Modify `Sources/StatusMenus/App/StatusMenusApp.swift`: change user-facing app names, status item labels, and window titles to AgentDock.
- Modify `Sources/StatusMenusCore/Models/MenuBarStatusSummary.swift`: change compact menu bar title from SKnife to AgentDock.
- Modify `script/build_and_run.sh`: stage `AgentDock.app` and the `agentdock` CLI binary.
- Modify `.gitignore`: ignore `.superpowers/` mockup session files.

## Task 1: Core Storage Analyzer

- [x] Write failing checks for recursive storage analysis, cleanup classification, and ranked nodes.
- [x] Implement `StorageAnalysis`, `StorageNode`, `StorageCleanupCandidate`, and `StorageCleanupRisk`.
- [x] Keep legacy `snapshot(...)` behavior for existing callers.
- [x] Run `swift run StatusMenusCoreChecks`.

## Task 2: CLI

- [x] Add the `agentdock` executable target.
- [x] Implement `status`, `storage scan`, `storage top`, `storage clean-plan`, `slock list`, `slock show`, `modules list`, and `app open`.
- [x] Support `--json` where it is most useful for automation.
- [x] Run `swift build` and smoke-test CLI commands.

## Task 3: App Identity And Slock Editor

- [x] Rename visible strings from StatusMenus/SKnife to AgentDock where they affect app branding.
- [x] Make the Slock name field read-only in the memory editor.
- [x] Keep description and memory sections editable.
- [x] Run `swift build`.

## Task 4: Storage V2 UI

- [x] Build a native SwiftUI operations deck with dark technical visual styling.
- [x] Render a treemap from `StorageAnalysis.rankedNodes`.
- [x] Show scan matrix, telemetry lines, ranked paths, and cleanup candidate selection.
- [x] Implement "Move to Trash" against selected cleanup candidates.
- [x] Run `swift build`.

## Task 5: Packaging And Verification

- [x] Update `script/build_and_run.sh` to stage `dist/AgentDock.app` and `dist/bin/agentdock`.
- [x] Run `swift run StatusMenusCoreChecks`.
- [x] Run `swift build`.
- [x] Run `./script/build_and_run.sh --verify`.
- [x] Smoke-test `dist/bin/agentdock status --json` and storage commands.

## Self-Review

- The plan covers the approved visual direction, CLI control, Slock read-only agent naming, and install staging.
- The cleanup path is intentionally Trash-based, not permanent deletion.
- Dynamic plugin installation remains future work; the new CLI and module registry keep that path open.
