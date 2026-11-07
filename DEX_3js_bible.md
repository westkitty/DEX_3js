# DEX 3js Project Bible

## Project identity and baseline — 2026-11-06

Canonical source: `westkitty/DEX_3js`. Existing SwiftUI/AppKit launcher with trusted `package.json` start, project profiles, protected process-group stop, last-good settings recovery, tool inventory and local CLI. Baseline commit `0cde5f7ac11367260b4946cb95aaa6489afeeb11`. Historical validation in `docs/VALIDATION.md` is evidence for 2026-11-04, not proof of today's MacBook installed binary.

## Control Center uplift in isolated Big Mac staging — 2026-11-06

**IMPLEMENTED IN STAGING / COMPILED AND SMOKE TESTED / UNCOMMITTED / MACBOOK INSTALLATION UNVERIFIED.** User explicitly requested a persistent GUI outside chat for the installed Three.js tools. The Control Center tab was implemented in a disposable, isolated Big Mac checkout; the MacBook's installed app and Museum source remained untouched at that point. The strongest useful changes are real four-endpoint health checks, one-click inspect with captured tree, Studio/Needle launch actions, project views, local-only URL enforcement, guarded child cancellation, and direct explanation of tool boundaries. No new dependencies or backend.

Source validation on Big Mac: `make test` PASS, `make integration-test` PASS, `make build` PASS, `git diff --check` PASS. Native process opened and remained alive with one 980×692 window; window capture failed due macOS capture restrictions. Real Museum/DevTools/Needle/Studio path on intended MacBook, accessibility, graphical acceptance, installation and live MCP client checks remain UNVERIFIED. Source is not committed/pushed. Full report: `docs/CONTROL_CENTER_VALIDATION_2026-11-06.md`.

**Protected constraints for continuation:** trust/approval, owned process-group safety, local-only service probing, install history, no Museum edits, no fabricated installed/connected statuses, no auto-apply source edits, no blanket repo reset. Reconcile only the staged diff, independently validate on the real MacBook, then finalize Git if required evidence passes. Preserve this ledger append-only.

## MacBook transfer and install — 2026-11-06

The exact candidate patch from the isolated Big Mac staging checkout matched its supplied SHA-256, passed `git apply --check`, and was applied to the clean MacBook repository. `make test`, `make integration-test`, `make build`, and `git diff --check` passed. `make install` copied the app to `~/Applications/DEX 3js.app`; installed executable hash matches the reviewed build. The built native UI started Museum of Me, returned the actual live Museum scene tree through the installed `3d-lab inspect` tool, and opened the Museum in Chrome with Needle Inspector enabled. Studio startup launched the local API and web services.

**NOT COMPLETE:** the desktop automation service timed out before post-install UI review and could not surface a permission prompt. Keyboard accessibility, failures/cancellation/recovery, Studio open UI, all profile shortcuts, and final unwanted-process review remain unverified. Do not claim final acceptance until those checks are observed in the installed window. Details are appended to `docs/CONTROL_CENTER_VALIDATION_2026-11-06.md`. No Museum files were changed; no commit, push, merge, or publish occurred.

## Installed dashboard acceptance follow-up — 2026-11-06

The installed `~/Applications/DEX 3js.app` window was subsequently reviewed after desktop automation recovered. From that installed app, Museum started and became reachable, its actual Three.js scene tree was inspected, and Stop reported graceful shutdown of the owned process group; PID/PGID and port 5173 were gone afterward. The installed inspector was cancelled once (exit 15), then retried successfully. The Studio web editor opened in Brave; Needle opened the Museum in Chrome with its extension enabled; Museum Workshop opened at `/?edit=1`. Basic Tab navigation moved focus to the saved Museum row. Only the requested Studio services and the installed DEX dashboard remain running.

Scope remains bounded: other profile shortcuts, VoiceOver, clipboard-copy behavior, and Studio failure recovery were not exercised. See the appended acceptance follow-up in `docs/CONTROL_CENTER_VALIDATION_2026-11-06.md`. No Museum source/assets/site changes, commit, push, merge, or publish.

Final runtime for this task: Museum is intentionally running under the installed DEX app (PID/PGID 51021) with a matching DEX ownership record; Chrome showed the Museum arrival screen and Needle Inspector access on the site. The installed Stop path was independently exercised and cleaned up the previous run. Studio API/web remain available from Start Studio. See the final state appendix in the validation receipt.
