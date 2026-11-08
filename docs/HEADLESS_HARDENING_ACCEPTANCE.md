# DEX 3js GUI acceptance

Browser workflows are separate and must be accepted separately:

- **DEX scene inspector:** Uses its isolated Puppeteer Chrome profile, verified CDP target, DEX-owned browser session and loopback proxy. Needle is not required in this profile.
- **Needle Inspector:** The **Open Needle in Chrome** action opens Museum in the normal Chrome profile where the user's installed Needle extension is available. It is a separate browser window/session and must not be conflated with the isolated DEX inspector.

Source and headless tests do not replace native-app observation. Preserve unrelated Chrome/Brave tabs and processes.

## Final candidate status — 2026-11-07

- **Candidate-only PASS:** Dark native dashboard opened with Museum selected; Museum launched from DEX; the live DevTools MCP connected to the real scene. On the final candidate session, one Cmd+Q exited DEX and stopped its managed Museum and inspector resources. This does not establish installed-app acceptance.
- **Journey 1A — DEX-owned isolated inspector: PASS (candidate).** Exact DEX-owned CDP target `DAA4EDE197BB033082B6AF9C55104F28`, proxy `http://localhost:49716/`; executable/profile, MCP parent/PGID and CDP port were tied to the live candidate session. Target-specific CDP screenshot `/tmp/dex-owned-museum-target.png` was visually reviewed and showed rendered Museum content with the Three.js MCP overlay. The native hierarchy, selection/details, search/filter, expansion, refresh and reconnect/session reuse worked. Temporary material preview and revert worked with the same target/proxy and no duplicate target. This was not the installed app.
- **Journey 1B — Needle in normal Chrome profile: PASS (candidate).** DEX's **Open Needle in Chrome** action reused normal Chrome at `127.0.0.1:5173/`. The installed Needle Inspector 2.9.0 DevTools panel was opened from Chrome's More tabs menu; its UI reported `Needle Inspector is active on 127.0.0.1:5173`. This is separate from the isolated Puppeteer target; Needle is not expected in that profile. No extension was installed or Chrome setting changed.
- **Journey 2 — VoiceOver: NOT TESTED — USER-DECLINED.** The user explicitly declined VoiceOver testing. No traversal or speech evaluation was performed; it is excluded from this milestone's mandatory acceptance criteria. Keyboard navigation is assessed separately below.
- **Journey 3 — restart and safe reattachment: PASS (disposable candidate fixture only).** A trusted disposable project and external `npm run dev` process used isolated settings under `/tmp/dex3js-external-survivor-gui`. DEX first exited without an owner record while the external process survived. After DEX closed, the matching test owner record was written; relaunch reconstructed disposable project/trust state and displayed `Running · recovered pid 65976`, after validating PID/PGID, start, executable, command and canonical cwd. A separate stale-start record was rejected; DEX displayed Stopped and left live PID 67525 untouched. Only that fixture-owned process group was cleaned. A separate ordinary candidate Museum session exited on one Cmd+Q and its managed server/inspector resources disappeared; the saved Museum profile remained available on the next candidate launch. Installed-app restart remains unverified.

## Headless closure evidence — 2026-11-07

The production `Store` initializer accepts an optional settings directory for isolated tests; the app continues to use its existing `~/Library/Application Support/DEX 3js` directory by default. `make test` runs `Tests/StoreLifecycleSmoke.swift` against the real `Store.save`, initialization/recovery, process-record validation, `start`, and `stop` paths. It verifies last-good recovery from a truncated primary settings file; a fresh Store reloading project identity and trust; reattachment only to a test-owned surviving npm dev process; rejection of stale and unrelated matching-PID records; repeated cancellation during emitted output; eventual timeout cleanup of a SIGTERM-ignoring fixture; exit-status reporting; parent/child group cleanup; and survival of a separate sentinel process. All resources use a disposable project, temporary settings, an isolated loopback port and a temporary home. This is **headless evidence**, not installed-app restart acceptance.

The previous app termination contract remains in force: the GUI termination handler requests cancellation and stops its managed project. The headless reattachment case intentionally models an externally surviving test process separately; it does not claim that a normally managed project should survive quitting DEX. See the newest validation entry for exact command results and residual GUI limits.

## 1A. Inspect the DEX-owned browser target

- **Initial state:** Open the installed DEX app; select the trusted Museum of Me profile. Confirm the project's server is running and the Inspector session manager is disconnected. Note existing browser windows and tabs without changing them.
- **Actions:** Connect the scene inspector. Verify the MCP process, isolated Chrome executable/profile, CDP port and target ID correspond to the session reported by DEX. Capture the target's own page through its authorized CDP screenshot capability. Refresh the native hierarchy; select an object; search/filter; expand a group; refresh and reconnect; confirm a healthy session is reused; preview a supported material property and revert it.
- **Expected visible result:** The exact tracked target renders the local Museum, not merely an HTTP page or scene-tree response. The native tree/details match the live scene. Repeated operations preserve the target and create no duplicate tab/session.
- **Failure signal:** Screenshot is from another browser, target/profile identity changes unexpectedly, scene pixels do not render, inspection controls fail, preview does not revert, or an unintended browser launches.
- **Required evidence:** Candidate/app identity, DEX session report, browser executable and exact private profile, MCP PID/parent/PGID, CDP port, target ID and proxy; target-specific rendered screenshot; native selected-object/details and preview/revert results. Redact private paths in shared records.
- **Safe cleanup/recovery:** Reconnect only through DEX. Use **Close DEX session** and confirm its owned MCP/browser resources are gone. Leave unrelated Codex, Chrome and Brave sessions untouched; do not close a tab based only on URL similarity.

## 1B. Verify Needle in normal-profile Chrome

- **Initial state:** Keep the isolated DEX scene inspector connected and record its target ID/proxy. Note existing normal-profile Chrome windows without changing them.
- **Actions:** Use DEX's **Open Needle in Chrome** action. Identify the newly opened or reused normal-profile Chrome window by its process/profile identity and exact Museum URL. Open the already-installed Needle extension through its Chrome toolbar; observe its actual panel and basic scene hierarchy/property inspection.
- **Expected visible result:** The normal Chrome profile renders Museum and the Needle panel operates. The isolated DEX session remains connected to the same target and proxy without additional tabs or process replacement.
- **Failure signal:** Wrong profile/URL, missing extension or panel, basic inspection unavailable, or the DEX session is disconnected/replaced.
- **Required evidence:** Normal-profile Chrome PID/profile and URL/title; visible Needle panel and basic inspection result; before/after DEX target ID/proxy and session state.
- **Safe cleanup/recovery:** Do not install extensions, change Chrome settings, purchase a license or close unrelated windows. Close only a test-created window when its ownership is certain.

## 2. Verify VoiceOver navigation

- **Initial state:** Open the installed DEX app with a project selected and scene hierarchy available. Record the current VoiceOver state. For this closure, VoiceOver was not exercised at the user's direction; acceptance remains NOT ACCEPTED.
- **Actions:** With the operator's normal VoiceOver setup, navigate the Control Center, inspector status/actions, hierarchy disclosures, selected-object label/details, preview and revert controls, and a disconnected/error state. Use keyboard navigation to traverse the same controls and observe focus.
- **Expected visible/audible result:** Controls have distinct names and actionable states; hierarchy disclosures expose expansion; selection is announced; status/error changes are perceivable; focus remains visible and proceeds in a usable order.
- **Failure signal:** Unnamed controls, missing disclosure/selection state, silent connection failures, hidden keyboard focus, or focus trapped in the scene panel.
- **Required evidence:** Human-observed VoiceOver traversal notes and the app build identity. Record OS/app versions and specific failures. A source audit or accessibility tree alone is not VoiceOver acceptance.
- **Safe cleanup/recovery:** Return VoiceOver to the operator's initial state. Restore the prior selected project and inspector state; do not change macOS privacy settings.

## 3. App restart and safe project reattachment

- **Initial state:** Save the installed app/build identity and project trust state. Confirm DEX's termination handler calls inspector cleanup and the normal managed-project stop path. Do not assume a project launched by DEX should survive app quit. Candidate ordinary-shutdown and disposable external-recovery journeys passed; installed-app restart remains pending.
- **Actions:** First verify ordinary DEX shutdown: quit the app, then confirm the DEX-owned inspector and managed project stop as requested. Separately, prepare a trusted project process that is intentionally external to DEX and survives DEX quitting; provide a matching valid owner record only through the supported test setup. Reopen DEX and observe startup recovery.
- **Expected visible result:** Ordinary managed shutdown leaves no owned project/inspector processes. In the separate externally surviving case, DEX restores the saved profile and reports Running/recovered only after validating PID, PGID, process start, command and working directory. A mismatch remains unclaimed and is not signaled.
- **Failure signal:** DEX claims a stale/reused PID, attaches to another project's process, signals an unverified group, loses saved settings, or reports recovery when the process has exited.
- **Required evidence:** Before/after DEX and project PIDs/PGIDs, owner-record identity with private paths redacted, displayed recovered state, and confirmation of saved project/trust settings. Retain an installed-app restart receipt before marking this journey fully accepted.
- **Safe cleanup/recovery:** Stop only the externally started process using its owning launcher. Remove only the disposable test record after confirming no owned process remains. Reopen the installed app and confirm ordinary project profiles/settings remain intact.

## Final keyboard and automated gate — 2026-11-07

- **Keyboard: PASS ON CANDIDATE.** With macOS Keyboard Navigation temporarily enabled for the test and restored to its original Off setting afterward, visible focus moved through project search/selection, Control Center project actions, scene search, hierarchy, selected-object details, connection controls and preview/revert. Space activated project start, connection/reconnection, hierarchy expansion, object selection, material preview/revert and session close. Filter selection and reset were keyboard-operable. A visible blue focus ring appeared on the preview value field. Disconnected/unavailable status was reported after stopping the test-owned project; start and reconnect recovered it. No focus trap was observed. This is candidate GUI evidence, not installed-app acceptance.
- **Automated gate at source `8db0d835c655137eec9912a7a9f1155ab32df6d9`:** `make test` PASS (10/10 browser lifecycle cycles, interrupted initialization/recovery, output framing/cancellation, store recovery and first-Quit cleanup, Control Center and appearance checks); `make integration-test` PASS (owned process identity/stop safety); `make build` PASS; `git diff --check` PASS. A first `make test` execution concurrent with other checks had a transient cycle-1 MCP abort timeout; a one-cycle diagnostic rerun and the full serial rerun passed without source changes. No CI result is inferred.
- **VoiceOver: NOT TESTED — USER-DECLINED.**
- **Installed-app verification: PENDING installation.** The installed bundle is not yet replaced or launched; its prior executable/helper hashes are retained in the current closure receipt.
