# Shared tool inventory

Snapshot from this Mac on 2026-11-04. A local path or registration is not a successful live connection. DEX 3js shows known facts and uses Unverified otherwise.

| Tool | Class | Observed status |
|---|---|---|
| Three.js DevTools MCP | STDIO MCP | Installed 0.5.0; Codex and Claude Code registration observed. Live connection is client-session dependent. |
| Needle Inspector | Chrome extension | Enabled 2.9.0; free hierarchy/property/performance inspection observed previously. Pro status unknown. |
| Official Three.js DevTools | Browser tooling | Unverified; no separate official tool installation established. |
| Chrome DevTools MCP | STDIO MCP | Not installed in shared toolkit. |
| Spector.js MCP | MCP server | Not installed; Spector.js itself is browser tooling, not this MCP server. |
| Playwright CLI | CLI/browser automation | Unverified in this audit. |
| Blender Lab MCP | MCP server | Not installed. Blender is present but arbitrary-code MCP is not enabled. |
| glTF Transform | Asset pipeline CLI | Unverified in shared PATH. |
| glTF Validator | Asset validation CLI | Unverified in shared PATH. |
| AI Three.js Studio | App + STDIO MCP | Present at pinned revision `fa2f5ebfa3286ffe836182e68be4d91cc9e12525`; API/web services stopped in latest doctor output. |
| Tweakpane | Project library | Not installed globally; project dependency only. |
| Theatre.js | Project library | Not installed globally. |
| Triplex | Project authoring tool | Unverified. |
| postprocessing | Project library | Present in Studio's dependency tree only, not globally reusable. |
| three-mesh-bvh | Project library | Not installed globally. |

No additional integrations were installed in this pass. This keeps the shared tool installation unchanged and avoids adding project runtime dependencies.
