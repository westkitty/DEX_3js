# DEX 3js Control Center — bounded implementation validation

Date: 2026-11-06 (America/Detroit; validation on 2026-11-07 UTC)
Target: `westkitty/DEX_3js`; isolated Big Mac staging checkout.
Baseline: `main` at `0cde5f7ac11367260b4946cb95aaa6489afeeb11`, clean on clone.

## Intent and protected capabilities

The native DEX 3js launcher remains the project/ownership authority. The update targets user friction: installed tools were mostly status labels, not usable controls. Protected: local-only operation, explicit project dev-script trust, owned dev-server stop behavior, configuration/last-good recovery, project profile URLs, project folder/editor actions, and separation of inspection from actual Museum of Me source mutation.

## Implemented (source)

1. New native **Control Center** landing tab: selected project, start/stop/open, configured project views, real connection checks for project URL, DevTools browser scene bridge, Studio API, Studio editor, and meaningful not-checked/stopped/awaiting-scene/error status distinctions.
2. One-click **Inspect live scene** through the installed shared `3d-lab inspect --project` command using a direct Process argument list, with captured output, copy action and cancellable owned child process. No source-edit action is exposed.
3. Start/open Studio and open the project's local URL in Chrome to use the installed Needle extension. Explicit explanatory copy prevents confusing separate Studio projects and ephemeral DevTools previews with changes in Museum source.
4. Local probe helper with strict loopback HTTP allowlist, two-second timeout, no redirect following, and test seam for mocked HTTP responses. Project action URLs also use local validation.
5. Readme, Control Center runbook, Makefile test wiring, and Foundation-only smoke fixtures.

## Verified

| Check | Result | Evidence |
| --- | --- | --- |
| Before-edit baseline `make test` | PASS | Original Swift typecheck and process-group smoke on Big Mac |
| New `make test` | PASS | SwiftUI/AppKit typecheck; loopback/bridge mock tests; existing process-group smoke |
| `make integration-test` | PASS | Existing disposable child group, stale PID and live orphan protections passed |
| `make build` | PASS | Native macOS binary produced by Xcode Swift compiler |
| `git diff --check` | PASS | No whitespace/error findings |
| Native process launch | OBSERVED | `open -n build/DEX 3js.app` returned exit 0; DEX3js process 44700 remained alive, window 484 with 980×692 bounds via Quartz |
| macOS window screenshot | BLOCKED | `screencapture -x -l 484` returned `could not create image from window` (capture permission/environment limit) |
| Real DevTools inspector on local Museum | NOT RUN | Staging Big Mac does not host the MacBook's shared `3d-lab` installation or local Museum server |
| Studio interaction through new dashboard | NOT RUN | No authenticated/full desktop UI journey recorded |
| MacBook app `make install` | NOT RUN | Target MacBook DEX//REACH command queue saturated with existing workloads; target not modified |
| Representative-device performance and UI accessibility | UNVERIFIED | Native typecheck is not a substitute for MacBook visual and input acceptance |

## Bug/decision ledger

- Previously static tool inventory gave no direct real connection proof → addressed by bounded loopback checks. The selected project probe intentionally reports endpoint reachability, **not** selected-project identity.
- Former Studio launch message implied startup success when only the process spawned → changed to explicit launch-requested wording.
- Project action execution paths formerly constructed URLs directly → new Control Center and existing Projects actions use validated loopback destinations.
- Inspect cancellation could leave managed child processes → now uses group termination only when the OS confirms the inspector PID is its process-group leader; otherwise terminate its direct process.
- Rejected: embedding a second complete Three.js scene editor into SwiftUI, installing new Three.js dependencies, visual spectacle with no engineering benefit, changing the Museum renderer.
- Deferred: stable native interactive object-property editing, cross-client MCP invocation proof, end-to-end Needle/Studio operation and proper screenshot/input acceptance on intended MacBook.

## Delivery state

**SOURCE IMPLEMENTED ON ISOLATED BIG MAC CLONE; BUILD/SMOKE VERIFIED; INSTALLED MACBOOK APP NOT UPDATED; GUI ACCEPTANCE NOT VERIFIED; NOT COMMITTED OR PUSHED.**

The source revision remains `0cde5f7` until authorized delivery is possible. Current implementation is an uncommitted working-tree diff on the staging machine and must not be represented as a shipped replacement app. No Museum repository changes, Git pushes or web deployments were made.

## Next decisive action

Once the intended MacBook command queue has capacity, transfer/reconcile this scoped diff into its authoritative `westkitty/DEX_3js` checkout without overwriting user changes, run native build and install against that machine, exercise the real Museum → DevTools → Studio/Needle user journey, inspect the actual window and accessibility/keyboard behavior, and then perform independent final diff/validation/Git delivery checks. Stop rather than claiming the installed app is current when any of these checks fail.

## MacBook transfer and acceptance continuation — 2026-11-06 (America/Detroit)

Target: the canonical MacBook checkout of `westkitty/DEX_3js`, `main` at baseline `0cde5f7ac11367260b4946cb95aaa6489afeeb11`. The exact Big Mac candidate patch was retrieved through the authorized DEX//REACH connection; the remote SHA-256 matched `f28faee831644a7342161a4d58474e53550778704b3c801be0f471834d58a0d0` and its 49,275-byte local copy passed `git apply --check` before application. The initial checkout was clean.

- `make test`: PASS; native typecheck, endpoint allowlist/bridge response fixtures, and process-group smoke passed.
- `make integration-test`: PASS; disposable group shutdown, stale empty leader handling, and live orphan preservation passed. The suite initially refused because an old DEX process record existed. The recorded leader/group were absent; the existing stop helper cleared only that stale record and signaled no process before the test was rerun.
- `make build`: PASS during the requested `make install` build.
- `git diff --check`: PASS.
- `make install`: PASS to `~/Applications/DEX 3js.app`, `~/.local/bin/dex3js`, and `~/.local/bin/dex3js-stop-owned.py`. Installed executable SHA-256 matches the built executable: `572eddaca3d1d5b01f62238e772e8014f051ea2c99cd50d8614627fb81dc9e8f`.
- Native UI review on the built copy: Control Center displayed the existing Museum of Me profile and shortcuts. Starting Museum returned a loopback-reachable project. `3d-lab inspect --project` connected to the actual Museum scene and returned its live scene tree; output stated source files untouched. Open Needle in Chrome displayed the actual local Museum page and Chrome showed Needle Inspector 2.9.0 enabled with site access.
- Studio launch was requested through the dashboard; its API (port 4000) and web editor (port 5180) were observed listening and returned HTTP 200. Dashboard refresh automation timed out before a fresh UI state could be recorded. The DevTools HTTP bridge at 9222 was unavailable after the one-shot inspection process disconnected, which is expected for that process lifetime.
- The inspected build was terminated before installation. `open -n` then launched the installed app; its process path is the installed bundle and its binary hash matches the inspected build. The desktop automation service timed out twice before it could reopen/read the installed window. Therefore post-install visual acceptance, keyboard accessibility, UI cancellation/failure recovery, Studio Open action, Museum route shortcuts, and unwanted-process review are **NOT VERIFIED**. No system permission dialog was surfaced by the desktop automation service to retrigger.
- Museum and Studio services launched for the requested workflow remain running. No Museum source, assets, or published site were modified. The repository remains uncommitted and unpushed.

**MacBook state: SOURCE APPLIED; TESTS/BUILD PASS; INSTALLED APP LAUNCHED AND BINARY MATCHES REVIEWED BUILD; POST-INSTALL VISUAL/ACCESSIBILITY ACCEPTANCE INCOMPLETE. Do not mark the mission complete until the installed window is reviewed and remaining GUI journeys are exercised.**

## Installed-window acceptance follow-up — 2026-11-06 (America/Detroit)

The desktop automation service recovered after the earlier timeout. The installed application at `~/Applications/DEX 3js.app` was opened and its native Control Center was reviewed. Its running executable is the installed path; SHA-256 remains identical to the previously inspected build.

- **Installed UI + saved project/settings:** the dashboard opened with the existing Museum of Me profile, its configured route shortcuts, and shared Studio status. No settings or project profile were changed.
- **Museum start/stop:** after cleaning up the explicitly task-owned process group from the earlier built-app pass, Museum started from the installed app as PID 44170, reported a reachable project URL, then Stop reported `Exited (15)` and `Sent graceful stop to DEX-owned process group`. The PID/PGID disappeared, port 5173 stopped listening, and the process record was absent.
- **Installed live scene inspection:** ran `3d-lab inspect` from the installed app and captured the actual Museum scene tree, including `museum [Scene]`, named meshes, groups and lights. Output stated the source files were untouched. A second run after cancellation also returned the live tree.
- **Cancellation/recovery:** Cancel inspection produced exit status 15 and returned the action to idle; a following inspection succeeded.
- **Studio/Needle/browser routes:** the installed dashboard opened AI Three.js Studio in Brave (`http://127.0.0.1:5180/`). Open Needle in Chrome showed the Museum site and Needle Inspector 2.9.0 enabled with site access. Museum Workshop opened in Brave at `http://127.0.0.1:5173/?edit=1` and displayed the actual Museum page. The Studio API/web rows were reachable; the short-lived DevTools bridge correctly returned unavailable after the one-shot inspector disconnected.
- **Keyboard/UI:** native accessibility output exposed labeled dashboard controls; Tab moved selection from the search field to the saved Museum row. This is a basic keyboard traversal check, not a complete VoiceOver or accessibility audit. The window was visually inspected. Failure recovery was exercised through unavailable project status → start/reachable → stop, plus inspector cancellation/retry.
- **Final process state:** the installed DEX dashboard remains open. Museum is stopped and leaves no DEX process record or server listener. Studio API/web remain running because the dashboard's requested Start Studio action launched them; pre-existing MCP server processes were not modified.

**UPDATED STATUS: INSTALLED APP VISUALLY/RUNTIME VERIFIED FOR THE TESTED WORKFLOWS.** Untested edge cases include the remaining Museum shortcuts individually, VoiceOver, copy-to-clipboard, and Studio service failure recovery. No commit, push, merge, or publish occurred.

## Phase 2 delivery and Phase 3 validation — 2026-11-07 (America/Detroit)

### Git delivery

- Phase 2 commit `94bce0748045a1e5959c35fbea284ff9d03b91f8` was pushed to `origin/feat/dex3js-native-scene-inspector`; remote readback matched that SHA.
- Phase 3 branch: `feat/dex3js-dark-browser-lifecycle`, based on the verified Phase 2 branch. No Phase 3 commit or push; `main` is unchanged.

### Phase 3 checks and installation

- `make test`: PASS after the final source/layout changes. This includes Swift typecheck, local endpoint/bridge smoke, process-group smoke, app appearance smoke, and an integration smoke using the installed MCP adapter that verifies two connects retain the same MCP PID and local proxy URL without a Chrome descendant.
- `make integration-test`: PASS on the Phase 3 source before launching the final GUI runtime; disposable process ownership, stale-record handling, and unrelated orphan preservation passed. The final Museum process was left intentionally running, so this check was not repeated over its active ownership record.
- `make build`: PASS; `make install`: PASS to `/Users/andrew/Applications/DEX 3js.app` and the existing per-user CLI/stop-helper locations.
- `git diff --check`: PASS after implementation and again after the final documentation append.
- Installed executable SHA-256: `2c5f64d633eedca6db566f2ba222bab53cfaa89343c6727f86a63a52313f2088`. Installed scene adapter SHA-256: `0235e03b370d8b7e4bb7da99e6a361c34394cbab9df5b2b8cac3d9632e626c3c`.

### Installed GUI/runtime evidence

- DEX was opened from the installed bundle. With macOS Appearance explicitly set to Light, its native window and Control Center (including the scene hierarchy/details and material controls) stayed dark. Projects, Toolbox, Diagnostics, and Configuration had also been inspected in the installed app. macOS Appearance was restored to the user's original Dark selection, and DEX remained dark.
- Museum of Me was running from DEX at PID `40946`, its configured local URL responded, and the installed MCP returned the live `museum` scene and `night-island-terrain` geometry/material details. Selection and scene refresh worked.
- A live material preview changed terrain roughness from `0.96` to `0.25`; individual Revert change restored it and the pending list returned to zero. No Museum source files were written.
- Inspector Disconnect reached the disconnected/cached-snapshot state. Inspect live scene then reconnected and returned a live scene tree.
- Start Studio was clicked. Its initial API check ran during startup and reported unavailable; the next explicit refresh reported both API (`127.0.0.1:4000/health`) and editor (`127.0.0.1:5180/`) reachable. Open Studio opened the editor in Brave.
- Tab navigation moved focus to the project search field. Existing configured Museum profile and shortcuts remained present.
- Process inspection showed no DEX-owned Chrome process. Two observed Chrome processes were children of pre-existing Codex MCP sessions and were left untouched. The default browser was Brave. The scene MCP adapter's regression run confirmed repeat connection retains one MCP PID and URL and starts no Chrome.

### Behavior and remaining limits

The repeated-launch trigger was the adapter's injected headed Puppeteer environment combined with an always-enabled Inspect action that tore down and relaunched an already active MCP transport. Phase 3 disables MCP browser auto-launch, uses one local proxy in the system default browser, reuses the active transport for repeated connects, and disables Inspect while connected. Passive health checks and dashboard navigation do not invoke browser creation.

An explicit Disconnect ends the DEX-owned MCP session. A subsequent explicit Inspect creates a new session on a new loopback proxy port and opens a new Brave tab. That recovery path returned a working scene; DEX could not verify browser-tab ownership, so it preserved the prior proxy tab rather than closing a possibly user-owned tab. Normal refresh, object selection and preview do not create tabs. A simulated close of a browser tab through desktop automation timed out, so that exact tab-close path is not independently verified. Chrome/Needle was an existing Phase 2 GUI-verified route and remains an explicit action; this Phase 3 pass did not click it again to avoid an unnecessary Chrome launch.

Museum Stop/restart ownership and route behavior were verified in the preceding Phase 2 installed receipt. The current final runtime intentionally leaves Museum and Studio running. VoiceOver and full keyboard audit were not performed. No Museum source, exhibits, assets, runtime files or published site were changed. No security setting was changed.

**Phase 2: COMMITTED AND PUSHED (remote SHA verified). Phase 3: SOURCE IMPLEMENTED, TESTED, INSTALLED, AND GUI/RUNTIME VERIFIED for the evidence above; uncommitted and unpushed.**

## Final requested running state — 2026-11-06 (America/Detroit)

After the installed Stop test passed, Museum was started again from the installed dashboard for the requested live workflow. Chrome displayed the Museum title/arrival screen at `127.0.0.1:5173/`; the Needle Inspector 2.9.0 toolbar control reported access to this site. DEX PID 51021 owns PGID 51021, and the owner-only process record matches the Museum working directory. Port 5173 is listening under that group. This is the intentional final runtime state, not an orphan; Stop was separately verified above. AI Three.js Studio API/web services also remain available from the requested Start Studio action.
