# StatusMenus Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable native SwiftUI macOS demo app with a modular shell, built-in enable/disable modules, auto-detected Slock state, and read-only storage/usage snapshots.

**Architecture:** Use a SwiftPM executable that stages into a local `.app` bundle. Keep app shell, module metadata, stores, services, and module views in separate files. Test non-UI logic first: module registry, Slock discovery/redaction, storage formatting, and usage parsing.

**Tech Stack:** Swift 6.2, SwiftPM, SwiftUI, AppKit, XCTest, Foundation, local macOS command-line tools.

---

## File Map

- Create `Package.swift`: SwiftPM package with `StatusMenus` executable and `StatusMenusTests`.
- Create `Sources/StatusMenus/App/StatusMenusApp.swift`: app entry point, regular Dock activation, main window, settings, optional menu bar scene.
- Create `Sources/StatusMenus/Models/ModuleID.swift`: stable built-in module identifiers.
- Create `Sources/StatusMenus/Models/ModuleStatus.swift`: status severity and labels.
- Create `Sources/StatusMenus/Models/ModuleDescriptor.swift`: module metadata.
- Create `Sources/StatusMenus/Stores/ModuleStore.swift`: enabled module persistence and selected module state.
- Create `Sources/StatusMenus/Services/Shell.swift`: small process runner.
- Create `Sources/StatusMenus/Services/ProcessParser.swift`: parse and redact process rows.
- Create `Sources/StatusMenus/Services/SlockDiscoveryService.swift`: scan Slock root dynamically.
- Create `Sources/StatusMenus/Services/StorageService.swift`: disk and folder snapshots.
- Create `Sources/StatusMenus/Services/UsageService.swift`: local top-process snapshot.
- Create `Sources/StatusMenus/Support/Formatters.swift`: byte, percent, and date helpers.
- Create `Sources/StatusMenus/Views/ContentView.swift`: root split view.
- Create `Sources/StatusMenus/Views/SidebarView.swift`: native module sidebar.
- Create `Sources/StatusMenus/Views/SettingsView.swift`: module toggles and preferences.
- Create `Sources/StatusMenus/Views/MenuBarStatusView.swift`: compact optional menu.
- Create `Sources/StatusMenus/Views/SharedViews.swift`: small reusable UI pieces.
- Create `Sources/StatusMenus/Modules/Storage/StorageView.swift`: storage demo dashboard.
- Create `Sources/StatusMenus/Modules/Slock/SlockAgentsView.swift`: Slock demo dashboard.
- Create `Sources/StatusMenus/Modules/Usage/UsageMonitorView.swift`: usage demo dashboard.
- Create `Sources/StatusMenus/Modules/ModuleManager/ModuleManagerView.swift`: module management dashboard.
- Create `Tests/StatusMenusTests/ModuleRegistryTests.swift`: built-in module coverage.
- Create `Tests/StatusMenusTests/SlockDiscoveryServiceTests.swift`: auto-discovery and redaction tests.
- Create `Tests/StatusMenusTests/ProcessParserTests.swift`: process parser tests.
- Create `Tests/StatusMenusTests/FormattersTests.swift`: formatting tests.
- Create `script/build_and_run.sh`: stable build/run/verify entrypoint.
- Create `.codex/environments/environment.toml`: Codex Run action.

## Task 1: Package And Failing Tests

**Files:**
- Create: `Package.swift`
- Create: `Tests/StatusMenusTests/ModuleRegistryTests.swift`
- Create: `Tests/StatusMenusTests/SlockDiscoveryServiceTests.swift`
- Create: `Tests/StatusMenusTests/ProcessParserTests.swift`
- Create: `Tests/StatusMenusTests/FormattersTests.swift`

- [ ] **Step 1: Create SwiftPM package and tests first**

Create a package named `StatusMenus` with an executable target and an XCTest target. Write tests that reference the desired APIs before production source exists.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test`

Expected: failure because production types such as `ModuleRegistry`, `SlockDiscoveryService`, `ProcessParser`, and `StatusFormatters` are not defined yet.

- [ ] **Step 3: Commit test baseline**

Run:

```bash
git add Package.swift Tests
git commit -m "test: define StatusMenus demo expectations"
```

## Task 2: Core Module Models And Store

**Files:**
- Create: `Sources/StatusMenus/Models/ModuleID.swift`
- Create: `Sources/StatusMenus/Models/ModuleStatus.swift`
- Create: `Sources/StatusMenus/Models/ModuleDescriptor.swift`
- Create: `Sources/StatusMenus/Stores/ModuleStore.swift`

- [ ] **Step 1: Implement the minimal module registry API**

Define `ModuleID`, `ModuleStatus`, `ModuleDescriptor`, `ModuleRegistry`, and `ModuleStore` so registry and persistence tests compile and pass.

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ModuleRegistryTests`

Expected: all `ModuleRegistryTests` pass.

- [ ] **Step 3: Commit module core**

Run:

```bash
git add Sources/StatusMenus/Models Sources/StatusMenus/Stores
git commit -m "feat: add module registry and store"
```

## Task 3: Services For Slock, Processes, Storage, And Usage

**Files:**
- Create: `Sources/StatusMenus/Services/Shell.swift`
- Create: `Sources/StatusMenus/Services/ProcessParser.swift`
- Create: `Sources/StatusMenus/Services/SlockDiscoveryService.swift`
- Create: `Sources/StatusMenus/Services/StorageService.swift`
- Create: `Sources/StatusMenus/Services/UsageService.swift`
- Create: `Sources/StatusMenus/Support/Formatters.swift`

- [ ] **Step 1: Implement service models and parsing**

Implement dynamic Slock discovery by scanning `<root>/agents`, `<root>/machines`, machine lock owner files, and trace metadata. Redact process commands before returning them to UI.

- [ ] **Step 2: Run focused tests**

Run:

```bash
swift test --filter SlockDiscoveryServiceTests
swift test --filter ProcessParserTests
swift test --filter FormattersTests
```

Expected: all focused tests pass.

- [ ] **Step 3: Commit services**

Run:

```bash
git add Sources/StatusMenus/Services Sources/StatusMenus/Support
git commit -m "feat: add local monitoring services"
```

## Task 4: SwiftUI Demo Shell

**Files:**
- Create: `Sources/StatusMenus/App/StatusMenusApp.swift`
- Create: `Sources/StatusMenus/Views/ContentView.swift`
- Create: `Sources/StatusMenus/Views/SidebarView.swift`
- Create: `Sources/StatusMenus/Views/SettingsView.swift`
- Create: `Sources/StatusMenus/Views/MenuBarStatusView.swift`
- Create: `Sources/StatusMenus/Views/SharedViews.swift`
- Create: `Sources/StatusMenus/Modules/Storage/StorageView.swift`
- Create: `Sources/StatusMenus/Modules/Slock/SlockAgentsView.swift`
- Create: `Sources/StatusMenus/Modules/Usage/UsageMonitorView.swift`
- Create: `Sources/StatusMenus/Modules/ModuleManager/ModuleManagerView.swift`

- [ ] **Step 1: Implement native SwiftUI app shell**

Build the regular Dock app, `NavigationSplitView`, settings window, optional menu bar scene, and four demo module views.

- [ ] **Step 2: Build**

Run: `swift build`

Expected: build exits 0.

- [ ] **Step 3: Run all tests**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 4: Commit app shell**

Run:

```bash
git add Sources
git commit -m "feat: add SwiftUI demo shell"
```

## Task 5: Run Script And Local Demo Verification

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [ ] **Step 1: Add run script and Codex action**

Create a SwiftPM GUI `.app` staging script with `run`, `--debug`, `--logs`, `--telemetry`, and `--verify` modes. Wire the Codex Run action to `./script/build_and_run.sh`.

- [ ] **Step 2: Verify build and launch**

Run: `./script/build_and_run.sh --verify`

Expected: script builds, stages `dist/StatusMenus.app`, opens it, and `pgrep -x StatusMenus` succeeds.

- [ ] **Step 3: Final verification**

Run:

```bash
swift test
./script/build_and_run.sh --verify
git status --short
```

Expected: tests pass, app launch verification passes, and only intended files are modified.

- [ ] **Step 4: Commit run support**

Run:

```bash
git add script/build_and_run.sh .codex/environments/environment.toml
git commit -m "chore: add local run workflow"
```

## Self-Review Notes

- Spec coverage: the plan covers native Dock app, optional menu bar, built-in modules, enable/disable state, Storage, Slock, Usage Monitor, Module Manager, Slock auto-discovery, privacy redaction, and local run verification.
- Scope: this is a runnable demo, not a full cleanup engine or dynamic plugin runtime.
- Slock requirement: no task hardcodes an agent UUID or machine ID; discovery is directory-based at refresh time.
