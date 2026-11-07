#!/usr/bin/env node
// Persistent, line-oriented adapter for the installed Three.js DevTools MCP.
import readline from 'node:readline';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { pathToFileURL } from 'node:url';

const root = path.join(os.homedir(), '.local/share/3d-lab');
const pkg = path.join(root, 'threejs-devtools-mcp/node_modules');
const entry = path.join(pkg, 'threejs-devtools-mcp/dist/index.js');
const sdk = path.join(pkg, '@modelcontextprotocol/sdk/dist/esm/client/index.js');
const stdio = path.join(pkg, '@modelcontextprotocol/sdk/dist/esm/client/stdio.js');
let client, transport, closed = false;
let sessionProject = '', sessionURL = '', sceneBrowserURL = '';
const say = (o) => process.stdout.write(JSON.stringify(o) + '\n');
async function shutdown() {
  if (closed) return;
  closed = true;
  await client?.close().catch(() => {});
  await transport?.close().catch(() => {});
  process.exit(0);
}
function decode(result) {
  if (result?.isError) throw new Error((result.content ?? []).map(x => x.text ?? '').join('\n'));
  const text = (result?.content ?? []).filter(x => x.type === 'text').map(x => x.text).join('\n');
  try { return JSON.parse(text); } catch { return { text }; }
}
async function connect(project, url) {
  if (url && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/?$/.test(url)) throw new Error('Project endpoint must be a local HTTP URL');
  if (client && sessionProject === project && sessionURL === (url ?? '')) {
    try {
      await call('bridge_status');
      return { connected: true, reused: true, browserURL: sceneBrowserURL };
    } catch { /* A failed MCP round trip invalidates this session; replace only this owned child. */ }
  }
  if (client) { await client.close().catch(() => {}); await transport.close().catch(() => {}); client = undefined; transport = undefined; }
  const { Client } = await import(pathToFileURL(sdk));
  const { StdioClientTransport } = await import(pathToFileURL(stdio));
  const freePort = () => new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => { const port = server.address().port; server.close(() => resolve(port)); });
  });
  const bridgePort = await freePort();
  const childEnv = { ...process.env, BROWSER: 'none', BRIDGE_PORT: String(bridgePort), ...(url ? { DEV_URL: url } : {}) };
  for (const key of ['PUPPETEER', 'CDP_PORT', 'CHROME_PATH', 'HEADLESS', 'HTTP_PORT', 'DEV_PORT']) delete childEnv[key];
  transport = new StdioClientTransport({ command: process.execPath, args: [entry], cwd: project,
    env: childEnv, stderr: 'inherit' });
  client = new Client({ name: 'dex3js-native-inspector', version: '1.0.0' }, { capabilities: {} });
  await client.connect(transport);
  const listed = await client.listTools();
  const names = new Set(listed.tools.map(x => x.name));
  for (const required of ['bridge_status', 'scene_tree', 'object_details']) if (!names.has(required)) throw new Error(`Installed DevTools MCP is missing ${required}`);
  sessionProject = project;
  sessionURL = url ?? '';
  sceneBrowserURL = `http://127.0.0.1:${bridgePort}/`;
  await call('bridge_status');
  say({ event: 'ready', tools: [...names] });
  return { connected: true, reused: false, browserURL: sceneBrowserURL };
}
async function call(name, args = {}) {
  if (!client) throw new Error('Inspector is not connected');
  const response = await client.callTool({ name, arguments: args });
  return decode(response);
}
async function dispatch(message) {
  const { id, op, args = {} } = message;
  try {
    let result;
    if (op === 'connect') { const result = await connect(args.project, args.url); say({ id, ok: true, result }); return; }
    if (op === 'close') { await shutdown(); return; }
    if (op === 'tree') {
      const deadline = Date.now() + 45_000;
      while (Date.now() < deadline) {
        const status = await call('bridge_status');
        if (status?.connected === true || /Bridge: connected/i.test(status.text ?? JSON.stringify(status))) {
          // Bound the response before decoding it into SwiftUI rows. Large Museum
          // subtrees can otherwise allocate an enormous recursive object graph.
          result = await call('scene_tree', { compact: false, depth: 4, maxChildren: 20 }); break;
        }
        await new Promise(resolve => setTimeout(resolve, 400));
      }
      if (!result) throw new Error('No browser scene connected. Open the project URL in a browser with the DevTools bridge enabled, then refresh.');
    } else if (op === 'details') result = await call('object_details', args);
    else if (op === 'preview') result = await call(args.tool, args.params);
    else if (op === 'pending') result = await call('pending_changes');
    else if (op === 'revert') result = await call('revert_changes', args);
    else throw new Error(`Unsupported inspector operation: ${op}`);
    say({ id, ok: true, result });
  } catch (error) { say({ id, ok: false, error: error.message ?? String(error) }); }
}
const input = readline.createInterface({ input: process.stdin });
input.on('line', line => { try { void dispatch(JSON.parse(line)); } catch (error) { say({ ok: false, error: error.message }); } });
input.on('close', () => { void shutdown(); });
process.on('SIGTERM', () => { void shutdown(); });
process.on('SIGINT', () => { void shutdown(); });
