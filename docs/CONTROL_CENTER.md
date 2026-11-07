# DEX 3js Control Center

## Purpose

The Control Center is a native Mac dashboard inside the existing DEX 3js launcher. It makes the **installed** Three.js tools usable without requiring the operator to memorize shell commands. It does not replace the browser scene editor, write into arbitrary projects, or silently commit experimental edits.

## First run

1. Open DEX 3js. Its initial tab is **Control Center**.
2. Select a Three.js project in the sidebar. Museum of Me can use the existing profile in `profiles/museum-of-me.json`.
3. If necessary, go to **Projects** and read/approve that project's `dev` script.
4. Choose **Start project**, then **Open project** or one of the configured project views.
5. Choose **Refresh connections**. The dashboard reports actual local HTTP responses: selected project URL, DevTools MCP scene bridge, Studio API and Studio web editor.
6. After DEX reports the project as running and has captured its local URL, choose **Connect** in **Inspector session manager**. DEX starts one installed DevTools MCP session and its isolated Chrome profile, verifies the browser process, target ID, and loopback proxy, then brings that existing target forward. The hierarchy is bounded; search/type filters and expand/collapse operate on returned scene data. Selecting a row requests actual `object_details` and shows returned transforms, geometry, material, light or camera properties.
7. Choose **Start Studio**, then refresh connections. **Open Studio** becomes available only when the Studio web interface responds.
8. Choose **Open Needle in Chrome** only when you need the Chrome-specific Needle extension. DEX opens a new window in Chrome's normal user profile, preserving its installed extensions and avoiding MCP automation profiles. Normal project and Studio pages open in the system default browser. Enable the Needle Inspector extension manually from Chrome's toolbar if required.

## What statuses prove

| Row | A successful result proves | It does *not* prove |
| --- | --- | --- |
| Configured project URL | **Reachable** means the validated local HTTP URL replied successfully | That the server belongs to the selected project, or that Three.js rendered |
| DevTools scene bridge | **Connected** means DEX's MCP session confirmed `bridge_status` and returned a live `scene_tree`; with no DEX session, the dashboard checks the default local status endpoint | That a desktop agent's MCP client registration is working |
| Studio API | **Reachable** means the local `/health` endpoint replied successfully | That a Studio project has been built or previewed |
| Studio editor | **Reachable** means the local web interface replied successfully | That authenticated or provider-backed features are available |

Other states distinguish Not checked, Checking, Connected, Awaiting scene, Unavailable, and Invalid endpoint. Probing is local-only, bounded by a two-second request timeout, and does not follow HTTP redirects. A selected project's URL must be plain `http://localhost` or `http://127.0.0.1`. No remote scanning or recurring background polling is performed.

## Editing discipline

- **Inspector session manager** reads `scene_tree`, `object_details`, and bridge status from the installed Three.js DevTools MCP. The adapter starts the installed MCP with one loopback-only CDP endpoint and a unique Puppeteer profile; it verifies the Chrome executable, process parent, profile, target ID and proxy URL before reporting the session as DEX-owned. DEX activates that exact target with CDP; it does not open a second tab. The project URL passed to the MCP server is restricted to local HTTP. The MCP selects a loopback proxy port dynamically to avoid collisions.
- Opening DEX, switching its tabs, refreshing connection health, selecting objects, and previewing or reverting material values do not launch browsers. **Reconnect** first asks the existing adapter to validate and reuse its MCP, browser target and proxy; an invalid managed session is released by the MCP before replacement. **Close DEX session** ends only the recorded private process group, waits for exit, and verifies cleanup. It does not terminate a browser process or tab unless that browser was launched in the session's isolated profile. If process ownership cannot be verified, group cleanup is refused and the UI reports that no replacement was started.
- A previous session opened proxy pages in the user's default browser and left old tabs without target ownership metadata. Those legacy tabs are preserved; URL matching alone is insufficient grounds to close them. New inspector sessions use isolated Chrome and never adopt or close those tabs.
- The separate shared `3d-lab inspect --project` CLI currently requests headed Puppeteer Chrome. DEX's native inspector does not invoke that CLI path. The **Open Needle in Chrome** button launches the installed Chrome executable with `--new-window` and the regular user profile, so the Needle extension remains available and Codex/other MCP automation profiles are not reused. Project/Studio URL actions use the system default browser.
- **Temporary material preview** is available for `roughness`, `metalness`, `opacity`, and `emissiveIntensity`, which the installed MCP exposes as numeric material properties. The selected row must resolve to an object with a compatible material. DEX displays the bridge's pending-change record, supports individual change IDs and **Revert all**, and never writes preview values to project source.
- The MCP scene tree response does not include object UUIDs. DEX addresses named objects by their returned dot path; duplicate names can be ambiguous when the MCP itself cannot distinguish them. Unnamed objects (and descendants beneath them) remain visible but are not selectable because the installed bridge provides no usable identifier. No stable object ID is invented.
- The native tree creates nested rows lazily and bounds each MCP response to depth 4 and 20 children per node so a very large Museum hierarchy cannot exhaust the dashboard. Groups with more children show the loaded/available counts; refresh re-reads the live scene without restarting DEX.
- Studio projects are separate, and Studio's MCP scene replacement has its own version check and rollback snapshot behavior. They are **not** a transparent editable mirror of Museum of Me.
- Needle's basic scene hierarchy and property inspection are useful without Pro; some editing/MCP capabilities require an additional license.
- Material/light live previews in Three.js DevTools are distinct from source writes. DEX does not expose a one-click `apply to production` action.
- This dashboard never edits Museum of Me code, assets, project Bible, or deployment as a side effect of inspection.

## Recovery

- **Project URL unavailable:** Start the trusted project, review its existing dev script and refresh connections after Vite reports readiness.
- **Bridge awaiting scene:** Activate the existing inspector target, check the project's local URL and page, then refresh or reconnect. Reconnect attempts the current session before creating a replacement.
- **Studio unavailable:** Start Studio and refresh. If it fails, inspect the shared `3d-lab` logs.
- **Inspect failed:** Read the native status and message. Use **Open inspector** to activate the verified target, then **Refresh scene**. If the target or proxy is stale, choose **Reconnect**; DEX verifies the old session and reports whether it reused or replaced it. **Copy report** copies session facts without project filesystem paths. If shutdown cannot be verified, the session stays marked unverified and DEX will not start a duplicate. The project dev server remains separately controlled by DEX's Start/Stop buttons.
- **Needle not visible:** Open the local project in Chrome, enable the extension from the toolbar, then inspect the browser.
- **No tool installed:** The dashboard explains the missing shared launcher rather than starting an unrelated executable.

## Verification scope

The dashboard must pass native macOS typechecking, the local endpoint/bridge mock tests, the real installed MCP session lifecycle cycles, process-group and ownership tests, build, and user-journey GUI review on the intended MacBook. Compiling does not prove the installed binary is updated. Compare executable and helper hashes after `make install`.
