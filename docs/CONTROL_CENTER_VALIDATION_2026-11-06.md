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

## Final requested running state — 2026-11-06 (America/Detroit)

After the installed Stop test passed, Museum was started again from the installed dashboard for the requested live workflow. Chrome displayed the Museum title/arrival screen at `127.0.0.1:5173/`; the Needle Inspector 2.9.0 toolbar control reported access to this site. DEX PID 51021 owns PGID 51021, and the owner-only process record matches the Museum working directory. Port 5173 is listening under that group. This is the intentional final runtime state, not an orphan; Stop was separately verified above. AI Three.js Studio API/web services also remain available from the requested Start Studio action.
