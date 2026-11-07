# DEX 3js

DEX 3js is a lightweight, local macOS project launcher for Three.js work. It uses SwiftUI/AppKit and the existing shared 3d-lab installation; it does not include a browser engine, backend, database, or copy of the MCP tools.

## Build and install

Requires macOS 13+, Swift 5.9+ and the macOS SDK. From this repository run `make install`, then open `~/Applications/DEX 3js.app` from Finder. The companion command installs as `~/.local/bin/dex3js`. `make run` builds and opens the development bundle; native source edits require rebuilding, while settings reload without a rebuild.

The app is locally ad-hoc signed by the linker. It has no Developer ID signature and is not notarized. `make uninstall` removes only the installed app and CLI. `make clean` removes the build output.

## Use

Add an existing project using the folder picker. DEX 3js checks for `package.json`, detects vanilla Three.js or React Three Fiber from dependencies and reports the lockfile package manager. Before the first launch, review the project's `dev` script and check the approval box. The launcher invokes the selected package manager's `run dev` script with an argument array, fixed working directory and `--host 127.0.0.1`; it doesn't evaluate config as shell code. The PID, process group, executable, start time and working directory record is stored locally with owner-only permissions. Stop validates these values before signaling only the app-owned group, then escalates to SIGKILL after two seconds if members remain. It does not kill arbitrary Node or browser processes. Quitting the app also requests shutdown for its project process group.

`dex3js doctor` reports local installation facts; it does not claim desktop MCP connection. `dex3js inspect --project PATH` delegates to shared `3d-lab inspect` for a real bridge connection attempt. `dex3js studio` delegates to the existing Studio launcher. `dex3js stop` validates the DEX-owned PID, process group, executable, start time and working directory before signaling it, then delegates to `3d-lab stop` for only its tracked process groups. When the recorded leader has exited, the stop helper clears a record only after confirming its process group is empty; a live orphan group is preserved rather than signaled without its leader identity.

## Configuration

User settings live at `~/Library/Application Support/DEX 3js/settings.json`, schema version 1. Writes are atomic and maintain `settings.last-good.json`; malformed settings are rejected and recover from the last valid file. Use Export settings for a backup. After an external IDE edits settings, choose Configuration → Reload from disk (or press Option-Command-R). Project profiles can also be imported/exported and reloaded from `dex3js.json`. Settings and process records are stored with owner-only file permissions. The application is intentionally data-only: no field contains an executable shell command. Example project metadata for the interoperable project format is in `examples/dex3js.json`.

## Control Center dashboard

DEX now starts on a **Control Center** tab. It keeps the existing project launcher while adding live local service status for a configured project URL, the Three.js DevTools scene bridge, Studio API, and Studio editor. It offers a one-click **Inspect live scene** workflow through the existing `3d-lab inspect` command, captures a real scene tree in the native window, and opens Studio or the selected project in Chrome for Needle Inspector. A reachable endpoint is not proof of Three.js rendering or an MCP client invocation. No new runtime dependency is installed.

See [docs/CONTROL_CENTER.md](docs/CONTROL_CENTER.md) for the exact actions, status meanings, editing boundaries, and recovery steps.

## Shared tools

The app shows the requested tool inventory with separate, conservative status values. MCP registrations and live connections are distinct. The application itself does not change Codex/Claude configuration. Confirm MCP invocation inside each desktop client's local project session. Integrations remain in `~/.local/share/3d-lab`; see `docs/TOOL-INVENTORY.md` for inventory. This release's current observed client result is recorded in `docs/VALIDATION.md`; neither a config entry nor CLI connectivity is desktop invocation proof. Never place credentials, browser profiles, node_modules, or private project paths in this repository.

## Project-specific launch actions

Use project `dex3js.json` (schema in `schema/project-profile.schema.json`) for names, URLs and relative page actions. The GUI can reload a file from the project, import/export a profile, and refresh app settings. A URL action is not a command and cannot execute code. The Museum profile in `profiles/museum-of-me.json` uses verified project entry points and the local Vite default; change its origin if the server selects another port.

## Agents

Codex Desktop uses `~/.codex/config.toml`; Claude Code in Claude Desktop uses `~/.claude.json` and project `.mcp.json` as appropriate. This is not Claude Desktop's regular Chat configuration. Restart each client after registration edits and verify tool invocation from a local Code-tab/project session. DEX 3js checks application presence and matching configuration entries, but labels live MCP connection unverified.

## Development and validation

`make test` performs Swift typechecking and a macOS process-group smoke test. `make integration-test` runs a temporary loopback development process through the CLI ownership validator and stop path; it refuses to overwrite an existing DEX process record. `make build` creates `build/DEX 3js.app`. `make install` copies the app, CLI and narrowly scoped stop helper to user locations. `make uninstall` removes those copies. The implementation is readable Swift source; configuration reload is live, native code changes require `make run` again.

## Security and limits

No network service or login item is created by DEX 3js. The app's Studio action delegates to the existing `3d-lab` process manager. The app does not change MCP configuration or install tools. Start commands require explicit per-project approval. A newly selected package script is untrusted. Project paths are passed as process working directories and commands are invoked with argument arrays; profile URL actions are data, not shell commands. The locally built app is ad-hoc signed by the linker, with no Developer ID signature or notarization. GUI-owned process shutdown and a disposable project path containing spaces were exercised; see `docs/VALIDATION.md` for remaining unverified cases. Tool status remains conservative and may show Unverified.

## Uninstall

Run `make uninstall` to remove only `~/Applications/DEX 3js.app`, `~/.local/bin/dex3js` and its stop helper. Remove `~/Library/Application Support/DEX 3js` manually if you also want to delete app settings and process records. Shared 3d-lab and all projects remain untouched.
