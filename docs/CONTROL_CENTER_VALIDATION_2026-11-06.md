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

## Phase 4 workstation and lifecycle validation — 2026-11-07 (America/Detroit)

### Phase 3 Git state

Phase 3 commit `30e6324b7b6f55eee4208c417822adf49fa17694` was already pushed to `origin/feat/dex3js-dark-browser-lifecycle` and read back at that SHA. Phase 4 is on `feat/dex3js-inspector-session-lifecycle`; no Phase 4 commit, push, merge, or publication was made.

### Changes and defect repair

- Kept the existing native SwiftUI app and installed Three.js DevTools MCP. The adapter launches one isolated Puppeteer Chrome profile, validates its MCP/browser parentage, profile, loopback CDP listener, proxy URL and exact target ID, serializes commands and shuts down the owned session through its MCP transport.
- The installed inspector could fail under host load because its global `ps` scan had a 1.2-second timeout. It now allows 5 seconds per process scan and up to 30 seconds to identify the launched target. Startup errors include bounded MCP diagnostics.
- A second observed defect was a stale `Stopped` label after DEX restarted while a recorded Museum process was still alive. Startup now revalidates the owner-only record against PID, process group, start time, trusted project and live working directory before restoring the project state. Stop rechecks ownership before signaling a recovered process group. An unverifiable record cannot authorize a signal.
- Lifecycle tests now run ten separate browser sessions, verify same-target reuse within each session, loopback-only CDP, error/reuse behavior, explicit close and adapter-EOF cleanup, and preservation of pre-existing Chrome PIDs. A concurrent unrelated Playwright Chrome process previously made the old global “no new Chrome PID” assertion fail; the test now checks its own isolated PID and confirms all baseline Chrome PIDs remain alive.
- Updated the existing README and Control Center guide. No Museum source, assets, exhibits, or published website were modified.

### Exact checks and installation

- `make test`: PASS. Node syntax; 10/10 isolated browser sessions; Swift typecheck; loopback/bridge smoke; forced-dark smoke; process-group smoke.
- `make integration-test`: PASS. Disposable managed group stopped; stale empty record cleared without signaling; live orphan preserved.
- `make build`: PASS.
- `make install`: PASS to `/Users/andrew/Applications/DEX 3js.app`, plus the existing user CLI and safe-stop helper paths.
- `git diff --check`: PASS after implementation and documentation review.
- Installed executable SHA-256: `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7` (matches `build/DEX 3js.app`). Installed `scene-bridge.mjs` SHA-256: `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0` (matches source).

### Installed runtime evidence

The installed native Control Center was reopened. Its saved Museum of Me profile and route shortcuts remained available. Museum started through DEX as PID/PGID `62596`; the project URL became reachable. DEX connected to the actual scene and the native hierarchy displayed `museum` with `exterior-world`, `lighting` and `museum-authored-placements`. Session status showed Connected, one exact Chrome target ID, one localhost proxy and a successful scene refresh. The CDP target list reported one page titled `Museum of Me — The Reliquary of Iterative Becoming` at the DEX proxy. The native Open Inspector action was invoked. Scene bridge/session was DEX-owned under helper PID/PGID `63772`, with MCP PID `63801` and isolated Chrome PID `63873`; the proxy was `127.0.0.1:52158` and CDP `127.0.0.1:52159`. These were live loopback listeners at final readback.

Studio API `/health` and editor on port `5180` returned successfully. At final readback there was one DEX-owned inspector session, one MCP, one isolated Chrome browser target/page, and one proxy. Two pre-existing Codex-owned MCP/Chrome pairs (Chrome PIDs `59719` and `61807`) remained present and were not signaled. The Museum owner record matched PID/PGID `62596` and its project directory. The running DEX app was the installed bundle.

### Limits and status

The Mac was under enough load that desktop automation calls sometimes took 20–29 seconds. The first post-install inspector launch exposed the 1.2-second process-scan timeout; after the source fix, the installed app connected successfully and returned the real scene. CUA's Chrome surface showed a separate test-controlled New Tab rather than the DEX isolated-profile window, so I did not claim a visual inspection of the Chrome canvas or Needle extension panel. The CDP target title and URL establish the live Museum target, not that its window was visually foregrounded. VoiceOver and full keyboard coverage were not performed. Store restart-recovery code compiled, but a second-app-instance recovery was not exercised. The previous App Management notification was not retriggered; no privacy/security setting was changed.

**Phase 4: SOURCE IMPLEMENTED, TESTS PASS, INSTALLED, AND LIVE MUSEUM SCENE VERIFIED IN THE NATIVE DASHBOARD. PARTIAL against the full GUI acceptance list: visible isolated-browser/Needle panel, VoiceOver, and app-restart reattachment remain unverified. Uncommitted and unpushed.**

## Phase 4 main integration and headless hardening — 2026-11-07

**Main integration:** Re-fetched and checked current refs. `origin/main` was `92f5727d99de901fa609e2fdd08f273bf86aabb7`; the feature revision was `bdbf1709f83204658f852c13bbc1e836a1342307`, with exactly three commits ahead and no divergence. The fast-forward push succeeded. A fresh fetch and `git ls-remote --heads origin main` read back `bdbf1709f83204658f852c13bbc1e836a1342307`; the three Phase 2–4 commits are ancestors. GitHub connector reported no commit statuses/workflow runs for the target and no PR; branch-protection status query was unavailable (HTTP 403), but the authorized non-force fast-forward push succeeded. No tag, release, deployment or Museum publication occurred.

**Hardening implementation:** Branch `feat/dex3js-headless-hardening` is based on that verified main revision in a managed isolated worktree. SwiftUI helper IPC is bounded to 1 MiB per line and fails pending requests with a recovery message before closing the existing verified inspector process group. The hierarchy and selected-object display have explicit accessibility names; changing inspector errors are marked as updates. `Tests/scene-bridge-lifecycle-smoke.mjs` now overlaps three connect requests, verifies reuse of the healthy target, replaces the isolated browser after a simulated test-owned Chrome crash, verifies project-path identity replacement, and continues the ten-cycle resource cleanup test. The test asserts the termination hook's existing app shutdown semantics: ordinary DEX termination requests managed project stop; GUI reattachment acceptance must separately cover an externally surviving trusted process.

**Headless checks:** `HOME=<disposable temporary home> make test` — PASS (10/10 isolated headless browser lifecycle cycles; duplicate connect convergence; bridge-disconnect retry; expired-target replacement; browser-crash replacement; stale CDP closure; project identity replacement; Swift typecheck; local endpoint/bridge smoke; dark appearance smoke; owned process-group smoke). This successful run used the installed toolkit through a read-only symlink and disposable temporary HOME. No user settings/process record was used by that run. No GUI check, app install, or VoiceOver session was performed.

**Deferred GUI acceptance:** Still **PENDING**, not inferred from compilation or automated tests: (1) visually inspect the actual DEX-owned target and Needle Inspector panel; (2) navigate the installed native UI with VoiceOver; (3) verify ordinary app shutdown and a separate safe reattachment to an externally surviving verified project. `docs/HEADLESS_HARDENING_ACCEPTANCE.md` lists initial states, actions, visible outcomes, failure signals, evidence and safe recovery for each.

**Execution note:** The first isolated test attempt had an invalid temporary `TMPDIR`; the existing MCP's browser-launch fallback opened a localhost proxy tab in the default browser. The attempt was stopped without tab manipulation; that tab was left untouched per the no-browser-intervention boundary. A subsequent failed isolated attempt did not launch a browser. The successful run used a disposable HOME with normal macOS temporary-directory behavior. Read-only process snapshots showed the installed DEX, Museum, Studio and previously existing browser/MCP processes still at their original PIDs/ports; no real application process was intentionally interrupted. No browser tabs were inspected, closed, or reorganized.

The hardening branch remains **uncommitted and unpushed**. This receipt is append-only; earlier Phase 4 GUI-acceptance statements remain **PARTIAL/PENDING**.

**Final check closure:** After the expired-target case was added, `HOME=<disposable temporary home> make test` passed again, including 10/10 cycles, concurrent-connect reuse, expired target replacement, test-owned browser crash replacement, stale CDP closure, project-path identity replacement, and cleanup. `HOME=<disposable temporary home> make integration-test` passed all three disposable process ownership cases. `make build` passed in the hardening worktree. `git diff --check` passed. The build remains a worktree artifact; `make install` was not run. Read-only process and listener checks at final review still found the installed DEX PID 62227, Museum group PID 62596/listener 5173, Studio listeners 4000/5180, DEX inspector helper/MCP/browser PIDs 63772/63801/63873 and its ports 52158/52159, and the two pre-existing Codex browser/MCP pairs 59488/59719 and 61737/61807. No process in that list was signaled by the hardening checks. The first failed isolated attempt's fallback-created localhost browser tab remains untouched; no tab was inspected or closed.

**Coverage limits for follow-up review:** The expanded automated scenarios do not simulate interruption mid-initialization, a dead MCP/bridge process or independently missing proxy, explicit port collision, failed process-group cleanup, or behavioral settings/process reconstruction across a new app instance. Existing source checks verify the termination policy and recovery guards; they are not substitutes for those behaviors. Accessibility changes are source-level labels/status semantics only. Focus order/visibility, contrast, reduced motion, expandable hierarchy announcements and actual VoiceOver remain unmeasured. These limits are retained for review rather than reported as passing.

## Headless hardening closure update — 2026-11-07

**Scope:** Work continued in `/Users/andrew/.codex/worktrees/dex3js-headless-hardening/DEX_3js` on `feat/dex3js-headless-hardening`, based on `bdbf1709f83204658f852c13bbc1e836a1342307`. No branch or commit was created. The installed app was not built into user locations or installed. Museum, Studio and existing browser processes were not intentionally signaled; the only browser processes created or killed were isolated headless Chrome instances owned by the fixtures.

**Browser fallback defect and repair:** The installed MCP's `launchBrowser` catches Puppeteer failure and invokes `open <proxy URL>` unless `BROWSER=none`. DEX had left `BROWSER` empty to allow the intended isolated Puppeteer browser, so a failed start reached macOS's default browser. The adapter now verifies `TMPDIR` by creating/removing a private temporary directory before MCP startup, prepends a bundled `open` refusal shim only to the MCP child's `PATH`, and detects MCP fallback diagnostics as a failed initialization. It does not set `BROWSER=none`, so explicit isolated Puppeteer startup remains available. Tests force the installed code's Puppeteer failure with a fake Chrome executable and test-only empty PATH; the `open` call reaches only the refusal shim, its URL is recorded in a disposable marker, and no browser PID is added. Missing and malformed temporary paths fail before an MCP child starts. Passive status likewise starts no MCP/browser.

**Automated failure matrix:**

| Case | Result | Evidence |
| --- | --- | --- |
| A. Interrupted initialization, partial cleanup, later explicit connect | PASS | `Tests/scene-bridge-lifecycle-smoke.mjs` `verifyInterruptedInitializationRecovery`; test fake Chrome fails once, then launches the isolated fixture successfully. |
| B. Missing proxy, passive failure and explicit bounded replacement | PASS | Lifecycle cycle 5 test hook points the existing fixture at a closed loopback port; status fails without replacement, explicit connect closes the stale CDP endpoint and creates a verified session. |
| C. Bridge/MCP crash state, prompt failure and safe reconnection | PASS | Cycles 6 and 7 kill only a verified fixture-owned MCP child; helper emits disconnected, a stale status request fails, and explicit reconnect cleans the verified browser before replacement. Pending native UI callbacks on real child termination are source-checked, not exercised in a running app. |
| D. Port collision and listener preservation | PASS | `verifyPortCollisionHandling`; an isolated listener remains responsive, installed MCP returns controlled `EADDRINUSE`, and browser/MCP baselines remain unchanged. |
| E. Cleanup refusal, no replacement and retry | PASS | Cycle 7 injects one fixture-only cleanup refusal; adapter reports the refusal, preserves the browser, then succeeds on one explicit retry. |
| F. New-app-instance persisted settings/process reconstruction | BLOCKED | Existing settings fallback, process identity validation and app-on-exit shutdown are source-checked. No behavior-level Store reconstruction test was added because Store currently binds its files to the real user's Application Support path; this phase did not add a broad persistence-injection refactor. Ordinary app exit intentionally stops its managed project, so external-survivor reattachment remains a separate scenario. |

The browser lifecycle suite completed **10/10** sequential isolated cycles in `make test`; a separate seven-cycle diagnostic run also passed the bridge-crash/cleanup-refusal cases. Each active fixture session asserted exactly one inspector page target and one DEX fixture MCP/Chrome pair, then verified MCP, Chrome, CDP and proxy cleanup. The suite preserved all Chrome and MCP process IDs present before its run. No CPU, memory, latency or cumulative resource measurement was collected, so no performance improvement is claimed.

**Output bounds:** Added `SceneOutputFramer` and its smoke test for small records, an exactly 1 MiB line, oversized terminated/unterminated records, malformed JSON, invalid UTF-8, truncated EOF and cancellation/reset. Results: PASS. Native helper termination now turns buffered partial output into a bounded readable failure and fails pending completions; overflow fails pending completions and requests cleanup via existing ownership checks. Actual GUI child-termination/cancellation interaction remains unverified.

**Accessibility source audit:** Added an explicit label and frequent-update trait to inspector status, a container label for the live hierarchy, an empty/selected-object announcement, a preview precondition hint, and status-update semantics for errors. Existing visible button names remain available. Source review found no demonstrated focus-order, focus-ring, contrast or reduced-motion defect to change without observing the native UI. Keyboard traversal details, disabled-state announcements, expand/collapse semantics and VoiceOver acceptance remain **UNVERIFIED**.

**Checks:** `make test` PASS (including 10/10 cycles and all cases A–E above; Swift typecheck; output framer; Control Center, appearance and process-group smokes). `make integration-test` PASS (disposable owner group stop, stale record clear without signal, live orphan preservation). `make build` PASS in the worktree. `git diff --check` PASS. These checks ran without the installed app or live user settings. The newly requested behavior-level case F did not pass because it was not run; overall hardening status is therefore **PARTIAL**, not complete.

**GUI status and Git boundary:** Actual DEX-owned browser/Needle panel, VoiceOver, and installed-app restart/reattachment remain **PENDING** in `docs/HEADLESS_HARDENING_ACCEPTANCE.md`. No GUI, `make install`, commit, push, merge, release, or Museum change was performed. The branch remains uncommitted and unpushed; see final `git status` for the preserved review diff.

## Final headless closure — 2026-11-07

**HEADLESS VERIFIED:** The Store reconstruction and native process gaps are now exercised by `Tests/StoreLifecycleSmoke.swift`, which compiles the actual `Store` implementation with only the app's `@main` entry omitted. `Store(settingsDirectory:)` injects a directory; the production default remains the existing user Application Support directory. The fixture calls production `Store.save`, creates a second independent Store, and confirms settings/project UUID/trust survive a truncated primary settings file through `settings.last-good.json`. It starts a disposable package project through `Store.start`, drops that Store, and has a fresh Store validate the still-running test-owned PID/PGID, start time, npm command and working directory. It then tests an expired start time and an unrelated `/bin/sleep` process recorded under its actual PID/PGID/start/cwd; neither is adopted or signaled. After Store-managed cancellation, another Store reports Stopped.

The native Store process test also waits for fixture output, calls `Store.stop` twice, verifies the owned parent/child process group exits and its process record is removed, and checks an unrelated test sentinel remains alive. A separate fixture ignores SIGTERM to exercise the existing two-second timeout/SIGKILL cleanup path; the sentinel survives. A further process is stopped only after its test record, PID and process-group identity are verified, and the Store reports `Exited (15)`. Chrome process IDs are sampled before and after this test and match. The test uses a disposable project and settings directory, an isolated loopback port, and a temporary `HOME` plus `CFFIXED_USER_HOME`; it does not access the installed app or live project settings.

This test exposed two defects in Store restart validation: `ps lstart` was split as fixed whitespace fields even though its field count varies, and symlink aliases for temporary project paths differed from `lsof`'s canonical cwd. Validation now queries PGID, start time and command separately, requires an approved package-manager executable/launch command, and compares canonical filesystem paths. These repairs preserve the app's normal shutdown contract: DEX still requests stop for its managed project on application termination. The automated external-survivor case is distinct from GUI application restart acceptance.

**HEADLESS VERIFIED:** `make test` — PASS, with fallback refusal and invalid TMPDIR tests, port collision/listener preservation, interrupted initialization retry, the ten-cycle browser lifecycle suite, output framing, Store reconstruction/process tests, Control Center probes, forced dark appearance and process-group smoke. The lifecycle suite reported **10/10** isolated sessions; each asserted one page target and successful MCP/Chrome/CDP/proxy cleanup, and all baseline Chrome PIDs remained. `make integration-test` — PASS (disposable managed group stop, stale empty group without signal, live orphan preservation). `make build` — PASS in the worktree. `git diff --check` — PASS after the final documentation update. No real Chrome/Brave session was launched or signaled by the Store test; the fallback test's `open` refusal marker remained within its disposable scratch directory.

**Test-fixture correction:** An early Store harness iteration used `URLSession` for a local readiness check. On macOS, Foundation wrote app-named cache files under `/Users/andrew/Library` despite temporary `HOME`. That readiness check was replaced by a raw loopback socket probe, `CFFIXED_USER_HOME` was added, and the two exact test-specific cache directories (`Library/Caches/dex3js-store-lifecycle-smoke` and `Library/HTTPStorages/dex3js-store-lifecycle-smoke`) were checked for open handles and removed. The passing rerun confirmed those directories were not recreated. No settings or process records were written there.

**REPORTED, not repeated here:** Earlier GUI observations in the historical Phase 4 entries—including the live Museum scene and Studio/Needle launch checks—remain prior receipts; this headless closure did not repeat them. The earlier accidental default-browser tab was left untouched.

**UNVERIFIED / PENDING:** Actual DEX-owned browser and Needle Inspector panel; VoiceOver and real keyboard-focus behavior; and full installed-app restart/reattachment under the normal project shutdown contract. Those three human-observed journeys remain in `docs/HEADLESS_HARDENING_ACCEPTANCE.md`. No app installation or release was made.

**Git delivery:** The reviewed hardening change set was committed as `ef047bf2afb5c76bd5d65bbb6c1fec29c6268aaa`, pushed to `origin/feat/dex3js-headless-hardening`, and independently read back at the same local, tracking and remote SHA. A documentation-only append records that delivery closure; no merge to main or release is part of this work.


## Final native acceptance attempt — 2026-11-07 — PARTIAL

Candidate: `feat/dex3js-headless-hardening` based on `f233f364ea7484ea58679e577784d6def15724de`; the shutdown repair is uncommitted. A native dark dashboard screenshot showed the trusted Museum profile and Control Center. Starting Museum through DEX produced a reachable local URL; the installed DevTools MCP connected to the live Museum scene, returned its scene tree and object details, and a temporary roughness preview was reverted. Studio launch was requested and a subsequent refresh reported both Studio API and editor reachable. The isolated inspector status exposed a target ID and loopback proxy. CUA could not display that owned Chrome window: its Chrome surface resolved to the separate Codex automation New Tab. The Needle action launched a normal-profile Chrome window for `http://127.0.0.1:5173/`, but its page and extension panel were not visually observed. That test-created window was left open.

Tab traversal reached the scene-search field with a visible focus ring in a screenshot. Full keyboard navigation and VoiceOver traversal were not completed; VoiceOver state could not be established without entering macOS accessibility settings, which were left unchanged. The external-survivor reattachment GUI scenario was not run.

Normal managed shutdown exposed a defect: Quit stopped the DEX-launched Museum process and disconnected the scene session, but the DEX app remained open until a second Quit. A bounded candidate repair now defers termination until Store cleanup completes and treats zombie-only process-group entries as exited. A fresh GUI repeat still left the DEX process/window open after the first Quit, so this repair is **NOT ACCEPTED**. The app was closed on the second Quit. No DEX app, Museum server, inspector listener or Studio web service remains from the test. The Studio processes started for this acceptance were stopped with the existing `dex3js stop` owner-aware workflow; pre-existing Codex MCP/Chrome processes were preserved.

Automated evidence: an initial post-repair `make test` passed, including 10/10 isolated browser cycles and the disposable Store shutdown cleanup case. Later full reruns failed in the DevTools lifecycle test: one attempt timed out during cycle 1 connect; another detected a transient extra test Chrome PID during interrupted-initialization cleanup (the PID was gone on the subsequent process read). `make integration-test` passed with a disposable HOME. `make build` passed; final candidate executable SHA-256: `28158e7c8643a20a7792fd3a7d3e83fc61f519ac7de39d093f705b0a90d979f1`. `git diff --check` passed. The installed application was not changed; its executable remains `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7` and its scene helper remains `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0`. The existing settings and last-good file SHA-256 values remained `83f8917481183830c9d64a929df7c24fecdac185fce7ff1fa09a8a26fb7b0bbc`.

**Decision:** PARTIAL. Needle panel, real VoiceOver, external-survivor GUI recovery and first-quit native shutdown are not accepted. Because a mandatory GUI gate failed and the latest full `make test` rerun failed, no files were staged, committed or pushed; main was not merged; no app was installed. Remote main remains `bdbf1709f83204658f852c13bbc1e836a1342307`, and remote feature remains `f233f364ea7484ea58679e577784d6def15724de`. Museum source, exhibits, assets and published website were not changed.

## Corrected final candidate verification — 2026-11-07 — PARTIAL

This receipt supersedes the earlier same-day **failed candidate** first-Quit and rerun-test results above. The final source candidate was rebuilt after the shutdown state-machine and browser-identity test corrections. `make test` passed on that source, including ten interrupted-initialization recovery attempts, ten mixed lifecycle cycles and the production `TerminationHandshake` smoke; `make integration-test`, `make build` and `git diff --check` also passed. The actual candidate app executable SHA-256 was `80264eb3862a23f7786eaae85e68f7a776cf091e2e47c544510ae283a1d4d186`; bundled `scene-bridge.mjs` SHA-256 was `258db7b29384ca590042a254cab5708ce3bf83c248d7874998cfb11916814ae8`.

At 15:54 EST, candidate PID 45498 opened the native dark Control Center with the saved Museum profile selected. Museum was started from the dashboard as process group 45717; its Vite server PID 45780 served the project. The real DevTools MCP connected to the live scene; the native panel displayed target `93C404FFC5C4D4E4AB8F406948151E51`, proxy `http://localhost:65326/`, scene `museum`, and its live hierarchy. This is candidate GUI evidence for the DEX-owned scene bridge. A separate earlier browser observation verified the Needle panel in a normal-profile Chrome window, but the Needle panel was not observed in the DEX-owned target during this final run; the combined DEX-target/Needle journey remains pending.

Exactly one Cmd+Q was sent to candidate PID 45498 at about 15:56:45 EST. By 15:57:07, the DEX process, managed project group (including Vite/esbuild), and inspector proxy listener were absent. No second Quit or force termination was issued. The pre-existing DevTools MCP PID 23431, Studio editor PID 23565, and normal-profile Chrome PID 25084 remained. This proves the candidate process exited and the managed project resources were cleaned on the first request. The app was not installed; this is not installed-app acceptance. The selected project/settings stayed available in the fresh candidate launch; external-survivor GUI reattachment was not tested.

The final acceptance remains **PARTIAL**: VoiceOver navigation and external-survivor reattachment were not exercised, and the required combined DEX-owned browser/Needle-panel journey remains unverified. No macOS security/privacy settings were changed. Installed app hashes remain executable `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7` and helper `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0`; no install occurred. User settings hash remains `83f8917481183830c9d64a929df7c24fecdac185fce7ff1fa09a8a26fb7b0bbc`. Remote main remains `bdbf1709f83204658f852c13bbc1e836a1342307`; at this receipt, remote feature remains `f233f364ea7484ea58679e577784d6def15724de`. Because automated checks now pass and incomplete GUI state is documented, the reviewed repair may be committed/pushed on the feature branch only. Merge to main and installation remain gated on the outstanding acceptance.

**Feature delivery readback — 2026-11-07:** Repair commit `774464b10ca2103a7d79ed4f6059c61558023c27` is present on local `feat/dex3js-headless-hardening`, its upstream tracking ref and `origin/feat/dex3js-headless-hardening` (independent `git ls-remote` readback). GitHub commit status is pending with no status contexts and zero check runs returned; no CI pass is claimed. Remote `main` remains `bdbf1709f83204658f852c13bbc1e836a1342307`. Worktree was clean after the push. No merge or install was performed because native acceptance remains partial.

## One-run final closure — 2026-11-07 — PARTIAL

The latest candidate in the hardening worktree was visually opened in the native dark Control Center. DEX's isolated inspector target `DAA4EDE197BB033082B6AF9C55104F28` and proxy `http://localhost:49716/` were tied to their MCP/browser process and profile identities. A target-specific CDP screenshot at `/tmp/dex-owned-museum-target.png` was visually reviewed and showed rendered Museum content plus the Three.js MCP overlay. Native hierarchy expansion, object selection/details, search/type filtering, refresh, reconnect/reuse, material preview and revert worked without changing project source or adding another inspector target.

The Control Center's **Open Needle in Chrome** action reused the normal Chrome profile at `127.0.0.1:5173/`. Needle Inspector 2.9.0 opened from Chrome's DevTools panel selector and reported `Needle Inspector is active on 127.0.0.1:5173`. Needle is separate from DEX's isolated Puppeteer profile and is not expected inside that profile.

GUI lifecycle evidence used a disposable trusted project and temporary HOME/settings directory only. A test-owned `npm run dev` process survived DEX quitting while DEX had no record for it. With DEX closed, the supported owner record was written and a fresh candidate displayed `Running · recovered pid 65976`, matching PID/PGID, start time, executable, command and canonical project cwd. A wrong-start-time record was rejected separately; DEX showed Stopped and left live PID 67525 untouched. Only the isolated test process group was cleaned. In the normal Museum journey, one candidate Cmd+Q stopped its managed server and inspector. The production Museum profile remained present in the user's normal settings.

The user directed “no voice over.” No VoiceOver traversal or speech acceptance was performed; System Settings showed the VoiceOver toggle off at final review. Keyboard observations remain limited to Tab movement among project search, selected project, scene search and preview value; complete order and focus visibility are not accepted. Installed-app restart was not performed. Therefore overall acceptance remains **PARTIAL**; no final main merge or installation is justified by these candidate-only results.

No source was changed during this closure. Previously recorded `make test`, `make integration-test` and `make build` results apply to the unchanged source at `8db0d835c655137eec9912a7a9f1155ab32df6d9`; this turn ran the documentation diff check. Installed executable/helper hashes remain `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7` and `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0`. User settings SHA-256 remains `83f8917481183830c9d64a929df7c24fecdac185fce7ff1fa09a8a26fb7b0bbc`. Museum source, assets and publication were not modified. Remote feature remains `8db0d835c655137eec9912a7a9f1155ab32df6d9`; remote main remains `bdbf1709f83204658f852c13bbc1e836a1342307`.

## Final release gate follow-up — 2026-11-07

**Keyboard: PASS ON CANDIDATE.** Native keyboard navigation with visible focus operated project search and selection, project launch/Control Center actions, scene search, hierarchy disclosure, object selection/details, connection/reconnect/session close, preview/revert, filter popup and disconnected/recovery controls. Space activated the tested controls; visible focus ring was observed; no focus trap was observed. macOS Keyboard Navigation was restored to its original Off setting after testing. **VoiceOver: NOT TESTED — USER-DECLINED** and excluded from this milestone's mandatory gate.

Final serial verification at candidate source `8db0d835c655137eec9912a7a9f1155ab32df6d9`: `make test` PASS, including `10/10` isolated browser cycles, interrupted-startup recovery, safe ownership/cleanup, cancellation and first-Quit shutdown; `make integration-test` PASS; `make build` PASS; `git diff --check` PASS. A previous execution concurrent with other checks produced an intermittent first-cycle MCP abort timeout; a one-cycle diagnostic rerun and the complete serial rerun passed without source changes. GitHub CI remains unverified unless separately reported by the remote.

At this checkpoint source work is candidate-accepted but not released. Installed DEX remains the prior app: executable SHA-256 `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7`, helper `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0`. Both settings files remain SHA-256 `83f8917481183830c9d64a929df7c24fecdac185fce7ff1fa09a8a26fb7b0bbc`. Installed-app launch and runtime proof remain pending. The source tree built at `build/DEX 3js.app` is only a candidate and is not installation evidence. Museum source, assets and published site were not modified.

## Installed application release receipt — 2026-11-07

Remote `main` source revision `f6d9c66e3837ea2fbc46f2b8753e97fed80c96c4` was read back before building and installing. `make install` completed. Installed app `/Users/andrew/Applications/DEX 3js.app` hashes match the tested build: executable `80264eb3862a23f7786eaae85e68f7a776cf091e2e47c544510ae283a1d4d186`; helper `258db7b29384ca590042a254cab5708ce3bf83c248d7874998cfb11916814ae8`. Rollback bundle `/Users/andrew/Applications/DEX 3js.rollback-20261107.app` was copied and verified at prior hashes `1bc57384d7dca0af7d441c1c92003aa72491c5c0e7f625da5b0e18fa851efed7` (executable), `cf9a2476cde28a9dcd5b632bb89f29d788a1c5f6209c6c1425f2a4f16ece11c0` (helper).

Installed GUI evidence: dark Control Center opened with saved trusted Museum of Me profile/path. Museum started under PID 67634. Installed inspector connected to the actual scene at target `D85EC91429B2474C68E584DE8046CB53`, proxy `http://localhost:63179/`; the live hierarchy showed Scene `museum`, and selected mesh `garden-lawn-west` returned `_BoxGeometry`, `MeshStandardMaterial`, transform and material values. Temporary roughness preview 1 → 0.25 was applied and reverted; pending changes returned to zero. Reconnect reported recovery/reuse of the same owned target and proxy. **Open Needle in Chrome** launched normal-profile Chrome at `127.0.0.1:5173/`; installed Needle Inspector 2.9.0 was active, and its hierarchy/inspector showed the same selected mesh.

Exactly one Command-Q on installed DEX reported graceful stop of the verified managed process group and inspector. Readback showed Museum PID 67634 exited, project server port 5173 and inspector proxy/CDP port 63179 gone, while pre-existing Studio PID 23565 and Three.js MCP processes remained. Normal-profile Needle Chrome PID 72747 remained as its separate browser workflow. The installed bundle was reopened; Museum returned selected and trusted with project stopped. `settings.json` and `settings.last-good.json` remain SHA-256 `83f8917481183830c9d64a929df7c24fecdac185fce7ff1fa09a8a26fb7b0bbc`. Keyboard: PASS on candidate. VoiceOver: **NOT TESTED — USER-DECLINED**. No CI checks were reported by GitHub; no CI pass is claimed. Museum source, exhibits, assets and deployment were unchanged.
