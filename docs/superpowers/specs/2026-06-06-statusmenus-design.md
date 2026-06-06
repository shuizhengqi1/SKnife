# StatusMenus macOS app design

Date: 2026-06-06

## Goal

Build a native SwiftUI macOS app that acts as a modular local control center. Version 1 focuses on built-in modules that can be enabled or disabled easily:

- Storage analysis and safe cleanup
- Slock agent monitoring
- Local usage monitoring
- Module management

The app is a normal Dock app with an optional menu bar status item.

## Context

The project workspace is currently an empty git repository at `/Users/xingege/Documents/statusmenus`.

Slock is treated as a local-daemon-backed agent system. Public Slock material describes agents running on the user's computer through `npx @slock-ai/daemon`, and the current machine has local Slock state under `~/.slock`.

Observed local Slock paths:

- `~/.slock/agents/12859a73-9740-46b0-a796-b7336634c7d4`
- `~/.slock/machines/machine-7b1809655b96dfb5`
- `~/.slock/machines/machine-7b1809655b96dfb5/traces`
- `~/.slock/machines/machine-7b1809655b96dfb5/daemon.lock/owner.json`

The app must not display token file contents or full daemon command arguments.

## Product shape

StatusMenus is a native SwiftUI app with:

- `WindowGroup` main window so it appears as a regular Dock app.
- Optional `MenuBarExtra` controlled from Settings.
- `Settings` scene for preferences and module toggles.
- `NavigationSplitView` main layout.
- Native macOS sidebar style for modules.

The first screen is the actual app, not a landing page.

## Main window

Sidebar:

- Shows enabled modules only.
- Uses one icon, one title, and one optional status line per module.
- Keeps disabled modules out of the main workflow.

Detail pane:

- Shows the selected module dashboard.
- Provides module-specific actions.
- Uses system-adaptive SwiftUI colors and materials.

Toolbar:

- Refresh current module.
- Open Settings.
- Shows primary module action when useful.

Settings:

- Enable or disable each built-in module.
- Toggle menu bar status.
- Choose refresh interval.
- Configure safety options for cleanup.
- Configure Slock root path if the default `~/.slock` is not correct.

## Module architecture

Version 1 uses built-in modules, not dynamic plugins.

Core types:

- `AppModule`: module metadata and view factory contract.
- `ModuleID`: stable identifiers for modules.
- `ModuleRegistry`: central registration point for built-in modules.
- `ModuleStore`: app-wide state for enabled modules, selected module, refresh interval, and menu bar preference.
- `ModuleStatus`: lightweight state such as healthy, warning, inactive, unavailable, or loading.

Adding a future built-in function should require:

1. Create a module folder.
2. Add its models, service, and SwiftUI views.
3. Register the module in `ModuleRegistry`.
4. The module appears in Settings and can be enabled or disabled.

This keeps v1 simple while leaving a clear path to a real plugin system later.

## File structure

Use a SwiftPM macOS GUI app layout:

- `Package.swift`
- `Sources/StatusMenus/App/StatusMenusApp.swift`
- `Sources/StatusMenus/Views/ContentView.swift`
- `Sources/StatusMenus/Views/SidebarView.swift`
- `Sources/StatusMenus/Views/SettingsView.swift`
- `Sources/StatusMenus/Models/*.swift`
- `Sources/StatusMenus/Stores/*.swift`
- `Sources/StatusMenus/Services/*.swift`
- `Sources/StatusMenus/Modules/Storage/*`
- `Sources/StatusMenus/Modules/Slock/*`
- `Sources/StatusMenus/Modules/Usage/*`
- `Sources/StatusMenus/Modules/ModuleManager/*`
- `Sources/StatusMenus/Support/*`
- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

The run script builds a project-local `.app` bundle and launches it, so the Codex Run button can use one stable command.

## Storage module

Purpose:

- Show disk capacity, used space, available space, and high-level storage health.
- Analyze large folders in user-selectable roots.
- Suggest cleanup candidates.

V1 analysis targets:

- Home directory top-level folder sizes.
- User caches such as `~/Library/Caches`.
- Downloads folder.
- Trash size.

Safety:

- Default behavior is read-only scanning.
- Cleanup shows a preview before any delete action.
- Deletion uses Trash where possible, not permanent removal.
- System paths and hidden token/config files are not cleaned automatically.

Implementation notes:

- Prefer Foundation APIs for filesystem metadata.
- Use narrow shell commands only where macOS APIs are unnecessarily slow or complex.
- Long scans run asynchronously and support cancellation.

## Slock Agents module

Purpose:

- Show whether the Slock daemon appears active.
- Show known agent workspaces under `~/.slock/agents`.
- Show workspace size, recent activity, and trace file activity.
- Show CPU and memory usage for Slock-related processes.
- Provide safe actions: open workspace, copy path, reveal traces, refresh.

Inputs:

- `~/.slock/agents`
- `~/.slock/machines`
- `daemon.lock/owner.json`
- Trace JSONL filenames and file metadata
- Process list filtered for Slock-related processes

Privacy and safety:

- Do not read or display token files under `~/.slock/agent-proxy-tokens`.
- Do not show full daemon command arguments because they may contain credentials.
- Do not mutate Slock state in v1.
- Do not start or stop agents in v1 unless explicitly added later.

Status model:

- Healthy: daemon-like process found and lock owner exists.
- Warning: local state exists but no active process is detected.
- Inactive: no Slock state or process found.
- Attention: recent trace file suggests errors, if parseable without exposing sensitive payloads.

## Usage Monitor module

Purpose:

- Show local CPU, memory, disk, and top process usage.
- Help users understand what is consuming system resources.

V1 data:

- CPU load summary.
- Memory used and available summary.
- Disk capacity summary.
- Top processes by CPU and memory.

Implementation notes:

- Use native process/system APIs where reasonable.
- Use `ps` or similar system tools for an initial top-process snapshot if needed.
- Refresh on a timer only while the module is visible or menu bar status needs it.

## Module Manager module

Purpose:

- Give users a dedicated place to manage built-in functions.

Capabilities:

- Enable or disable modules.
- Show module status and descriptions.
- Keep Storage, Slock, Usage Monitor, and Module Manager registered as built-ins.

The Module Manager itself cannot be disabled in v1, so users always have a way to re-enable other modules.

## Menu bar status

The menu bar item is optional.

When enabled, it shows a compact status summary:

- Storage available percentage or warning.
- Slock daemon status.
- CPU or memory pressure summary.

The menu should stay short:

- Open StatusMenus
- Refresh
- Per-module compact status lines
- Quit

Long details always open the main window.

## Error handling

Expected failures:

- Missing permissions for some folders.
- Slow or cancelled scans.
- Slock not installed or not running.
- Malformed or evolving Slock trace files.
- Shell command unavailable or returning unexpected output.

Behavior:

- Modules show partial data when possible.
- Errors are localized to the module pane.
- The app never crashes because one module failed.
- Sensitive paths or command arguments are redacted in UI output.

## Testing and verification

Build verification:

- `./script/build_and_run.sh`
- `./script/build_and_run.sh --verify`

Unit tests:

- Module registry contains required built-ins.
- Enable/disable persistence works.
- Storage byte formatting and safe cleanup candidate classification.
- Slock path discovery and process redaction.
- Usage monitor parsing for representative process output.

Manual verification:

- App launches as a Dock app.
- Main window appears at launch.
- Settings opens from toolbar/menu.
- Modules can be enabled and disabled.
- Slock module detects the existing `testAgent` workspace path.
- No token files or full Slock daemon command arguments appear in UI.

## Non-goals for v1

- Dynamic third-party plugin runtime.
- Downloading or installing separate apps.
- Starting, stopping, or controlling Slock agents.
- Deep package-manager security scanning.
- Permanent deletion of cleanup candidates.
- App Store sandboxing and notarization.

## Open decisions

- Final app display name can remain `StatusMenus` unless a better name is chosen before packaging.
- Slock trace content parsing should start shallow and metadata-first; deeper parsing can be added once the file schema is understood.
