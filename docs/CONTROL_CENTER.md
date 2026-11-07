# DEX 3js Control Center

## Purpose

The Control Center is a native Mac dashboard inside the existing DEX 3js launcher. It makes the **installed** Three.js tools usable without requiring the operator to memorize shell commands. It does not replace the browser scene editor, write into arbitrary projects, or silently commit experimental edits.

## First run

1. Open DEX 3js. Its initial tab is **Control Center**.
2. Select a Three.js project in the sidebar. Museum of Me can use the existing profile in `profiles/museum-of-me.json`.
3. If necessary, go to **Projects** and read/approve that project's `dev` script.
4. Choose **Start project**, then **Open project** or one of the configured project views.
5. Choose **Refresh connections**. The dashboard reports actual local HTTP responses: selected project URL, DevTools MCP scene bridge, Studio API and Studio web editor.
6. With a real Three.js dev server running, choose **Inspect live scene**. This starts the existing `3d-lab inspect --project <selected path>` command with an argument array (not a shell), displays returned scene-tree output, and supports cancellation/copy.
7. Choose **Start Studio**, then refresh connections. **Open Studio** becomes available only when the Studio web interface responds.
8. Choose **Open Needle in Chrome** to open the selected local project in Chrome. Enable the Needle Inspector extension manually from the browser toolbar if required.

## What statuses prove

| Row | A Reachable result proves | It does *not* prove |
| --- | --- | --- |
| Configured project URL | The validated local HTTP URL replied successfully | That the server belongs to the selected project, or that Three.js rendered |
| DevTools scene bridge | The bridge status endpoint replied with `connected: true` | That a desktop agent's MCP client registration is working |
| Studio API | The local `/health` endpoint replied successfully | That a Studio project has been built or previewed |
| Studio editor | The local web interface replied successfully | That authenticated or provider-backed features are available |

Other states distinguish Not checked, Checking, Awaiting scene, Unavailable, and Invalid endpoint. Probing is local-only, bounded by a two-second request timeout, and does not follow HTTP redirects. A selected project's URL must be plain `http://localhost` or `http://127.0.0.1`. No remote scanning or recurring background polling is performed.

## Editing discipline

- **Inspect live scene** is read-only with respect to the project source. The existing DevTools bridge may open its own browser instance; losing the browser bridge causes inspection to fail with visible output.
- Studio projects are separate, and Studio's MCP scene replacement has its own version check and rollback snapshot behavior. They are **not** a transparent editable mirror of Museum of Me.
- Needle's basic scene hierarchy and property inspection are useful without Pro; some editing/MCP capabilities require an additional license.
- Material/light live previews in Three.js DevTools are distinct from source writes. DEX does not expose a one-click `apply to production` action.
- This dashboard never edits Museum of Me code, assets, project Bible, or deployment as a side effect of inspection.

## Recovery

- **Project URL unavailable:** Start the trusted project, review its existing dev script and refresh connections after Vite reports readiness.
- **Bridge awaiting scene:** Keep the browser scene open, confirm the DevTools MCP connection from the relevant agent's Code session, then re-run inspection.
- **Studio unavailable:** Start Studio and refresh. If it fails, inspect the shared `3d-lab` logs.
- **Inspect failed:** Read the captured output; cancellation stops only the DEX-launched inspection process.
- **Needle not visible:** Open the local project in Chrome, enable the extension from the toolbar, then inspect the browser.
- **No tool installed:** The dashboard explains the missing shared launcher rather than starting an unrelated executable.

## Verification scope

The dashboard must pass native macOS typechecking, the local endpoint/bridge mock tests, the existing process-group and ownership tests, build, and user-journey GUI review on the intended MacBook. Compiling on a second macOS machine does not prove the installed MacBook binary is updated. `make install` updates the local app only when explicitly executed on the target.
