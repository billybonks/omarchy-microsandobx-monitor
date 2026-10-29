# Microsandbox for Omarchy

A native Omarchy top-bar widget and dropdown for your **existing local microsandbox installation**. This is not a TUI, WebView, or second desktop-shell process.

- Cube icon and running count in the bar; right-click to refresh.
- Dropdown with sandbox status, image, CPU/memory allocation, and published ports.
- Usage bars show CPU cores consumed versus allocated, and guest memory used versus its live limit.
- Start detached, stop gracefully, or remove a stopped sandbox after confirmation.
- Open the existing `msb ssh` or `msb logs -f` in an Omarchy terminal.
- Refresh every 3 seconds while open, every 15 seconds while closed; manual refresh at any time.
- Theme-aware appearance through Omarchy's own UI components.
- Each sandbox starts collapsed, showing CPU/RAM percentages in its header. Click the header or press Enter/Space to reveal details and controls; compact percentages disappear while expanded.
- Expansion is tracked by sandbox identity, so refreshes and reordered rows preserve it for the current panel session.
- Arrow keys/j/k select; Enter/Space expands/collapses; s opens a shell; g follows logs; x asks to remove; r refreshes; Escape closes. Start/stop uses its explicit button inside the expanded details.

## Architecture

`ui/DisclosureWidget.qml` and `ui/SandboxDisclosure.qml` implement the Omarchy interface. `ui/Service.qml` only launches the backend and assigns its JSON response to UI properties. There are no `.js` files, but QML still uses small JavaScript event handlers/bindings.

`microsandbox-panel` is a compiled Rust executable using the official **microsandbox 0.7.11 SDK**, pinned to match the installed `msb 0.7.11` runtime. Management does not scrape CLI output or generate shell scripts. Only interactive shell/log sessions use the existing CLI via direct argument arrays and `omarchy-launch-tui`.

The backend is short-lived: one invocation per refresh or user action. It explicitly selects `LocalBackend`, ignoring cloud backend selection from ambient API keys. It uses the SDK's existing home/config resolution, with no install/ensure/download calls. Runtime embedding/downloading and cloud features are disabled at compile time. Runtime, firmware, registry credentials, and sandbox state remain managed by microsandbox.

This does **not** turn microsandbox into a self-contained standalone runtime binary. An existing matching runtime and firmware are required. Building also downloads Rust crate dependencies from crates.io.

## Requirements

- Omarchy with Quickshell and its native plugin API (developed against Omarchy 4.0.4).
- An existing, working local **msb 0.7.11** installation, including firmware and KVM permissions.
- Rust stable, Cargo, and native build tools to compile the backend; users of an already built backend do not need Rust.
- The existing Omarchy terminal launcher for shell and log actions.

If your runtime is upgraded, review SDK compatibility and update the exact SDK dependency and lockfile together before rebuilding. The SDK accesses microsandbox's database, so avoid arbitrary SDK/runtime version mismatches.

## Build and install

```sh
make test
make check
make install
make enable
```

`make install` builds with `--locked`, copies only the runtime files into `~/.config/omarchy/plugins/local.microsandbox/`, validates that folder, and rescans plugins. `make enable` adds it to the right section of the bar. No sudo, system service, keybinding, or desktop-shell restart is required.

The Makefile uses `~/.cargo/bin/cargo` by default. Override `CARGO=/path/to/cargo` when necessary.

```sh
omarchy bar move local.microsandbox --section right
omarchy-shell shell summon local.microsandbox '{}'
omarchy-shell shell hide local.microsandbox
omarchy plugin disable local.microsandbox
omarchy plugin remove local.microsandbox
```

Removing the plugin does not remove the source checkout, `msb`, or any sandbox.

## Safety boundaries

- The QML plugin runs unsandboxed inside Omarchy, as all native plugins do. The Rust helper runs with your user permissions. Neither is a new security boundary.
- Refresh only requests metadata. The SDK may initialize/open its normal database and perform its own bookkeeping; this is not a forensic read-only database client.
- No start, stop, or removal is triggered automatically.
- Actions carry both a name and stable sandbox identity. A removed/recreated sandbox cannot silently become the target of an old UI action; SDK receiver methods also check identity.
- Delete is only offered for a stopped/crashed sandbox, requires confirmation, and never implicitly force-stops it. Deletion removes managed sandbox data; back up important data first.
- Status has a 20-second deadline; actions have a 180-second deadline and a UI watchdog. A timeout does not guarantee rollback: refresh before retrying.
- No network listener, central daemon, telemetry, sudo, downloaded installer, or generated Bash.
- Starting a sandbox may cause normal SDK/runtime network activity. Its existing network/mount/secret configuration still applies.
- Full sandbox configuration, environment variables, and secrets are never sent to QML. Display fields are bounded and rendered as plain text.
- Lists are explicitly paginated and capped at 500 sandboxes. Counts describe the displayed subset if truncated.
- Shell and logs are trusted interactive terminal streams; they are not parsed or sanitized by this plugin. CLI launch uses a `--` option separator.
- Errors keep previous rows visible but disable actions and show that the state is stale.

## Resource usage

Usage comes from the SDK's shared-memory metrics reports; it does not execute monitoring commands inside the guest. A sample timestamp is shown, and samples marked stalled/exited are not presented as live usage. If metrics are disabled or unavailable, the allocation and management controls remain visible.

CPU is displayed in cores used / allocated cores, with the bar normalized to the allocation. The sampler reports 100% per busy core: 100% raw usage on a two-core sandbox is **50% of its allocation**, not 100%. These are runtime-accounted CPU readings, not an in-guest process breakdown.

Memory is guest memory in use / the live guest limit, not the host process's RSS. Live resizing is reflected by the metrics reports. Missing guest memory readings are labeled unavailable rather than presented as zero where distinguishable; the SDK represents some temporarily unavailable readings as zero during resize, so readings can briefly be inaccurate while the guest converges.

## Backend protocol

```sh
./target/release/microsandbox-panel status
./target/release/microsandbox-panel start NAME ID
./target/release/microsandbox-panel stop NAME ID
./target/release/microsandbox-panel remove NAME ID
./target/release/microsandbox-panel shell NAME ID
./target/release/microsandbox-panel logs NAME ID
```

Each invocation prints one bounded JSON object with `ok`, `error`, `sandboxes`, `runningCount`, and `truncated`, and exits nonzero on error. Identity values are opaque tokens obtained from `status`. The backend CLI has no confirmation prompt; confirmation is a UI responsibility.

## Validation

`cargo test` covers request validation, command allowlisting, display sanitization, identity mismatch rejection, error response shape, usage normalization, missing readings, and progress-bar bounds. `qmllint` checks QML with the installed shell imports; dynamic Omarchy properties can produce static-analysis warnings. Live checks should inspect `qs log -p "$OMARCHY_PATH/shell" --tail 100` after enable/summon.

Integration testing against a user's existing sandboxes must be limited to listing and deliberately wrong-identity requests. Do not start, stop, or remove a real sandbox just to test the UI.
