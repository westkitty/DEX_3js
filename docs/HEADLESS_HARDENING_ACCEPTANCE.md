# DEX 3js deferred GUI acceptance

These checks require the installed Mac app and a person observing the screen. They remain **PENDING**; source tests and headless browser tests do not substitute for them. Do not run them until the operator has time to observe the session.

## Headless closure evidence — 2026-11-07

The production `Store` initializer accepts an optional settings directory for isolated tests; the app continues to use its existing `~/Library/Application Support/DEX 3js` directory by default. `make test` runs `Tests/StoreLifecycleSmoke.swift` against the real `Store.save`, initialization/recovery, process-record validation, `start`, and `stop` paths. It verifies last-good recovery from a truncated primary settings file; a fresh Store reloading project identity and trust; reattachment only to a test-owned surviving npm dev process; rejection of stale and unrelated matching-PID records; repeated cancellation during emitted output; eventual timeout cleanup of a SIGTERM-ignoring fixture; exit-status reporting; parent/child group cleanup; and survival of a separate sentinel process. All resources use a disposable project, temporary settings, an isolated loopback port and a temporary home. This is **headless evidence**, not installed-app restart acceptance.

The previous app termination contract remains in force: the GUI termination handler requests cancellation and stops its managed project. The headless reattachment case intentionally models an externally surviving test process separately; it does not claim that a normally managed project should survive quitting DEX. See the newest validation entry for exact command results and residual GUI limits.

## 1. Inspect the DEX-owned browser target and Needle panel

- **Initial state:** Open the installed DEX app; select the trusted Museum of Me profile. Confirm the project's server is running and the Inspector session manager is disconnected. Note existing browser windows and tabs without changing them.
- **Actions:** Connect the scene inspector. Confirm the reported target ID, isolated browser profile and loopback proxy. Open that target from DEX, then inspect the browser window and Needle Inspector panel. Refresh the native hierarchy and select an object.
- **Expected visible result:** The same DEX-owned target displays the local Museum page and Needle panel; the native tree shows the live scene and selected-object details. Repeated refresh/selection stays in that target.
- **Failure signal:** Target identity changes unexpectedly, a second DEX inspector page appears, the page is not the Museum, Needle is unavailable, or the hierarchy/details stop updating.
- **Required evidence:** DEX status/report with target ID and proxy; observed browser URL/title and Needle panel; observed native scene tree and selected object. Redact private paths if capturing diagnostics.
- **Safe cleanup/recovery:** Reconnect only through DEX. Use **Close DEX session** and confirm its owned MCP/browser resources are gone. Leave unrelated Codex, Chrome and Brave sessions untouched; do not close a tab based only on URL similarity.

## 2. Verify VoiceOver navigation

- **Initial state:** Open the installed DEX app with a project selected and scene hierarchy available. Record the current VoiceOver state and do not change global accessibility settings without the operator.
- **Actions:** With the operator's normal VoiceOver setup, navigate the Control Center, inspector status/actions, hierarchy disclosures, selected-object label/details, preview and revert controls, and a disconnected/error state. Use keyboard navigation to traverse the same controls and observe focus.
- **Expected visible/audible result:** Controls have distinct names and actionable states; hierarchy disclosures expose expansion; selection is announced; status/error changes are perceivable; focus remains visible and proceeds in a usable order.
- **Failure signal:** Unnamed controls, missing disclosure/selection state, silent connection failures, hidden keyboard focus, or focus trapped in the scene panel.
- **Required evidence:** Human-observed VoiceOver traversal notes and the app build identity. Record OS/app versions and specific failures. A source audit or accessibility tree alone is not VoiceOver acceptance.
- **Safe cleanup/recovery:** Return VoiceOver to the operator's initial state. Restore the prior selected project and inspector state; do not change macOS privacy settings.

## 3. App restart and safe project reattachment

- **Initial state:** Save the installed app/build identity and project trust state. Confirm DEX's termination handler calls inspector cleanup and the normal managed-project stop path. Do not assume a project launched by DEX should survive app quit.
- **Actions:** First verify ordinary DEX shutdown: quit the app, then confirm the DEX-owned inspector and managed project stop as requested. Separately, prepare a trusted project process that is intentionally external to DEX and survives DEX quitting; provide a matching valid owner record only through the supported test setup. Reopen DEX and observe startup recovery.
- **Expected visible result:** Ordinary managed shutdown leaves no owned project/inspector processes. In the separate externally surviving case, DEX restores the saved profile and reports Running/recovered only after validating PID, PGID, process start, command and working directory. A mismatch remains unclaimed and is not signaled.
- **Failure signal:** DEX claims a stale/reused PID, attaches to another project's process, signals an unverified group, loses saved settings, or reports recovery when the process has exited.
- **Required evidence:** Before/after DEX and project PIDs/PGIDs, owner-record identity with private paths redacted, displayed recovered state, and confirmation of saved project/trust settings.
- **Safe cleanup/recovery:** Stop only the externally started process using its owning launcher. Remove only the disposable test record after confirming no owned process remains. Reopen the installed app and confirm ordinary project profiles/settings remain intact.
