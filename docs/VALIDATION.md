# Validation receipt — 2026-11-04

Scope: local DEX 3js macOS application and its shared-tool integrations. Results below were observed on the current MacBook Air (arm64, macOS 26.6.2 / Darwin 25.6.0). No Museum or Bible source was committed or pushed.

## Acceptance matrix

| Status | Check | Evidence / limit |
|---|---|---|
| PASS | `make test` | Swift source typecheck and process-group smoke test passed after the stop-state repair. |
| PASS | `make integration-test` | Disposable npm/Vite-style child group was stopped; empty stale group record cleared without signaling; active orphan group preserved without signaling. |
| PASS | Installed GUI identity/build | `~/Applications/DEX 3js.app`, display name `DEX 3js`, arm64 bundle, 1.1 MB; installed executable SHA-256 matched the built executable (`4737a32001505ab8a41e282489e4b754c5d412cc5ae0e8c361a31449ff5c71c6`). |
| PASS | Idle sample | The open installed app sampled at 0.0% CPU and 16.2 MB RSS in one `ps` observation. This is a single instantaneous sample, not an idle soak or benchmark. |
| PASS | GUI project selection | Museum selected and launched. A disposable vanilla Three.js project at a path containing spaces was added, selected, started on port 5191, opened, stopped and removed from the launcher; its source remained on disk. No toolkit copy was installed in it. |
| PASS | GUI Stop/restart | Museum GUI Stop reported `Exited (15)`, removed its owned npm/Vite processes and released port 5173. The independent project likewise released 5191. Museum restarted and stopped again. The unrelated `127.0.0.1:5190` Vite service continued responding throughout. |
| PASS | Museum Workshop route | DEX opened the local Museum at `http://127.0.0.1:5173/?edit=1`; Brave displayed the Museum title and route. |
| PASS | Real Museum scene bridge | The shared DevTools MCP stdio server connected to the actual Museum page. It returned the real scene tree, `night-island-water` ShaderMaterial, `night-exterior-floodlight` PointLight, and PerspectiveCamera values. Runtime snapshot: 60 FPS, 186 draw calls, 44,372 triangles, 36,573 vertices, 21 programs, 202 geometries and 4 textures. |
| PASS | Live preview and revert | Changed `garden-lawn-west` MeshStandardMaterial roughness from 1 to 0.2 with the DevTools MCP; pending changes identified it as live-preview-only. Revert returned roughness to 1 and cleared pending changes. No source file was changed. This was an MCP stdio diagnostic harness, not a Codex Desktop tool invocation. |
| PASS | Shared tool inventory | `3d-lab doctor` found Three.js DevTools MCP 0.5.0, AI Three.js Studio at `fa2f5ebfa3286ffe836182e68be4d91cc9e12525`, Node 26.13.0, npm 11.20.0, pnpm 12.16.1, official Needle Inspector Chrome extension 2.9.0 enabled, and Studio API/web reachable at loopback ports 4000/5180. |
| PASS | Configuration recovery | Malformed DEX settings were rejected with “keeping last known-good configuration”; the original settings file was restored byte-for-byte and its SHA-256 rechecked. Settings remained mode 600 and app support directory mode 700. |
| PASS | Loopback / unrelated-service preservation | DEX/Museum and Studio use loopback addresses. Port 5190 remained listening on `127.0.0.1` and returned HTTP 200; DEX stop did not touch it. |
| PASS | GitHub remote identity/empty state | `origin` resolves to `westkitty/DEX_3js`; remote HEAD was empty when checked. Local branch is `main`, with no commits yet. |
| PASS | Claude Code in Claude Desktop MCP invocation | In a local Code session, the user observed `bridge_status` connected and `scene_tree` returned the real Museum tree. `studio_list_projects` initially reached the MCP tool but failed because the separate Studio API was stopped. After `3d-lab studio` started its loopback API, the user retried in Claude and received three projects. |
| UNVERIFIED | Codex Desktop MCP invocation | The current Codex desktop session did not expose either Three.js server as callable tools. No desktop invocation was obtained. A local stdio harness is not a substitute. |
| PASS | Studio MCP project listing | The configured MCP command returned all eight tools in local validation. With the Studio API running, `studio_list_projects` succeeded in Claude and returned three local projects. |
| UNVERIFIED | Studio MCP authoring/build/preview | One Studio build attempt timed out; a separate supervised build was reported to complete with exit code 0 (693 transformed modules and a large-chunk warning). Scene creation, validation, build and preview through MCP were not verified in this pass. |
| UNVERIFIED | Broader Museum browser checks | The earlier standalone browser boot timed out and the broad Playwright run stopped after real-scene tests timed out at 120 seconds; the Workshop browser automation proof also failed. These are not DEX GUI failures, and no Museum source was changed here. The local DEX-opened Workshop URL and real scene MCP were independently verified above. |
| UNVERIFIED | Claude Changes comparison | The Code tab’s Changes view showed a large diff against the historical `feat/foundation` comparison base. No changes were made in that Code session; the Museum worktree’s existing Git status remains the authoritative local state. |
| UNVERIFIED | GUI stale-state recovery after external process exit | CLI stale-record behavior has regression coverage. GUI Stop was exercised, but a stale external process record was not injected into the running GUI. |
| UNVERIFIED | Finder-specific double-click | The final installed app launched through LaunchServices (`open -n`) and was observed in the native desktop. A Finder double-click was not separately recorded. |
| UNVERIFIED | Startup timing | No repeatable launch-to-ready timing was captured. |
| UNVERIFIED | Missing executable recovery | Malformed config recovery passed; the GUI’s missing project executable case was not separately injected. |
| UNVERIFIED | Needle browser visual inspection in this pass | Installed inventory and prior evidence report the official extension enabled; no fresh extension panel screenshot/inspection is included in this validation pass. Needle Pro license remains unknown; no paid functionality is claimed. |
| UNVERIFIED | Current desktop 15-tool inventory | `3d-lab doctor` reports the installed integration inventory; a fresh complete GUI/tool-by-tool inventory was not captured. |
| UNVERIFIED | Codex Desktop MCP invocation | Claude Code is now verified, but Codex Desktop still has no observed tool invocation. Do not treat this publication as proof of the two-client acceptance requirement. |
| UNVERIFIED | GitHub push/readback | The correct remote was empty at preflight. This receipt precedes the explicitly authorized push; publication state is recorded separately after remote readback. |
| NOT APPLICABLE | Developer ID / notarization | Optional for this local developer app. It is ad-hoc signed by the local linker; it has no Developer ID signature and is not notarized. |

## Confirmed repairs

- `bin/stop_owned.py` now clears an empty stale process-group record without signaling a reused process group, and preserves a live orphaned process group when its original leader is gone. Integration regression cases cover both.
- Switching selected projects and starting a project clears the previous server URL and process log, preventing the GUI from displaying a different project's stale status.
- `make run` uses `open -n` for a fresh development app instance.

## Remaining client-side action

Codex Desktop remains the outstanding dual-client check. Open this local DEX 3js project in Codex Desktop, refresh its MCP connections, then invoke DevTools `bridge_status` and `scene_tree` and Studio `studio_list_projects`. Capture the actual tool names and returned data. Do not infer success from config files, `codex mcp list`, `3d-lab doctor`, or CLI tests.

**Verdict: PARTIAL for dual-client acceptance; Claude Code and local DEX validation passed. Publication is separately authorized and recorded after push verification.**
