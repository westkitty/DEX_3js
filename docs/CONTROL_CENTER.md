# DEX 3js Control Center

## Purpose

The Control Center is a native Mac dashboard inside the existing DEX 3js launcher. It makes the **installed** Three.js tools usable without requiring the operator to memorize shell commands. It does not replace the browser scene editor, write into arbitrary projects, or silently commit experimental edits.

## First run

1. Open DEX 3js. Its initial tab is **Control Center**.
2. Select a Three.js project in the sidebar. Museum of Me can use the existing profile in `profiles/museum-of-me.json`.
3. If necessary, go to **Projects** and read/approve that project's `dev` script.
4. Choose **Start project**, then **Open project** or one of the configured project views.
5. Choose **Refresh connections**. The dashboard reports actual local HTTP responses: selected project URL, DevTools MCP scene bridge, Studio API and Studio web editor.
6. After DEX reports the project as running and has captured its local URL, choose **Inspect live scene**. The bundled `Resources/scene-bridge.mjs` adapter starts the installed DevTools MCP using its structured API and keeps the session open. The native hierarchy expands on demand; selecting a row requests actual `object_details` and shows the returned transforms, geometry, material, light or camera properties.
7. Choose **Start Studio**, then refresh connections. **Open Studio** becomes available only when the Studio web interface responds.
8. Choose **Open Needle in Chrome** to open the selected local project in Chrome. Enable the Needle Inspector extension manually from the browser toolbar if required.

## What statuses prove

| Row | A successful result proves | It does *not* prove |
| --- | --- | --- |
| Configured project URL | **Reachable** means the validated local HTTP URL replied successfully | That the server belongs to the selected project, or that Three.js rendered |
| DevTools scene bridge | **Connected** means DEX's MCP session confirmed `bridge_status` and returned a live `scene_tree`; with no DEX session, the dashboard checks the default local status endpoint | That a desktop agent's MCP client registration is working |
| Studio API | **Reachable** means the local `/health` endpoint replied successfully | That a Studio project has been built or previewed |
| Studio editor | **Reachable** means the local web interface replied successfully | That authenticated or provider-backed features are available |

Other states distinguish Not checked, Checking, Connected, Awaiting scene, Unavailable, and Invalid endpoint. Probing is local-only, bounded by a two-second request timeout, and does not follow HTTP redirects. A selected project's URL must be plain `http://localhost` or `http://127.0.0.1`. No remote scanning or recurring background polling is performed.

## Editing discipline

- **Inspect live scene** reads `scene_tree` and `object_details` from the installed Three.js DevTools MCP. It launches its own headed Chrome browser through that toolkit and uses dynamically selected loopback ports so it does not collide with another MCP session. The project URL passed to the MCP server is restricted to local HTTP. A disconnected browser reports an error that can be retried after opening the project.
- **Temporary material preview** is available for `roughness`, `metalness`, `opacity`, and `emissiveIntensity`, which the installed MCP exposes as numeric material properties. The selected row must resolve to an object with a compatible material. DEX displays the bridge's pending-change record, supports individual change IDs and **Revert all**, and never writes preview values to project source.
- The MCP scene tree response does not include object UUIDs. DEX addresses named objects by their returned dot path; duplicate names can be ambiguous when the MCP itself cannot distinguish them. Unnamed objects (and descendants beneath them) remain visible but are not selectable because the installed bridge provides no usable identifier. No stable object ID is invented.
- The native tree creates nested rows lazily and bounds each MCP response to depth 4 and 20 children per node so a very large Museum hierarchy cannot exhaust the dashboard. Groups with more children show the loaded/available counts; refresh re-reads the live scene without restarting DEX.
- Studio projects are separate, and Studio's MCP scene replacement has its own version check and rollback snapshot behavior. They are **not** a transparent editable mirror of Museum of Me.
- Needle's basic scene hierarchy and property inspection are useful without Pro; some editing/MCP capabilities require an additional license.
- Material/light live previews in Three.js DevTools are distinct from source writes. DEX does not expose a one-click `apply to production` action.
- This dashboard never edits Museum of Me code, assets, project Bible, or deployment as a side effect of inspection.

## Recovery

- **Project URL unavailable:** Start the trusted project, review its existing dev script and refresh connections after Vite reports readiness.
- **Bridge awaiting scene:** Keep the project's browser scene open, check the project's local URL, then refresh or reconnect the native inspector.
- **Studio unavailable:** Start Studio and refresh. If it fails, inspect the shared `3d-lab` logs.
- **Inspect failed:** Read the native status and message. Reconnect after correcting the local project URL or browser bridge. Disconnect closes the DEX-owned MCP/Chrome session; the project dev server remains separately controlled by DEX's Start/Stop buttons.
- **Needle not visible:** Open the local project in Chrome, enable the extension from the toolbar, then inspect the browser.
- **No tool installed:** The dashboard explains the missing shared launcher rather than starting an unrelated executable.

## Verification scope

The dashboard must pass native macOS typechecking, the local endpoint/bridge mock tests, the existing process-group and ownership tests, build, and user-journey GUI review on the intended MacBook. Compiling on a second macOS machine does not prove the installed MacBook binary is updated. `make install` updates the local app only when explicitly executed on the target.
