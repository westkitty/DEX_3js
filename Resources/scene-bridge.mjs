#!/usr/bin/env node
// Persistent, line-oriented adapter for the installed Three.js DevTools MCP.
// Its headed browser is launched by that MCP into Puppeteer's isolated profile;
// shutdown is delegated to the same MCP process that created it.
import readline from 'node:readline';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { mkdtemp, rm } from 'node:fs/promises';
import { existsSync, rmSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.join(os.homedir(), '.local/share/3d-lab');
const pkg = path.join(root, 'threejs-devtools-mcp/node_modules');
const entry = path.join(pkg, 'threejs-devtools-mcp/dist/index.js');
const sdk = path.join(pkg, '@modelcontextprotocol/sdk/dist/esm/client/index.js');
const stdio = path.join(pkg, '@modelcontextprotocol/sdk/dist/esm/client/stdio.js');
const sessionArg = process.argv.indexOf('--session-id');
const sessionID = sessionArg >= 0 ? (process.argv[sessionArg + 1] || randomUUID()) : randomUUID();
const headless = process.argv.includes('--headless');
const forceBrowserFallbackForTest = process.argv.includes('--test-force-browser-fallback');
const testSessionMutations = process.argv.includes('--test-session-mutations');
const reportBrowserIdentityForTest = process.argv.includes('--test-browser-identity');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browserFallbackGuard = path.join(path.dirname(fileURLToPath(import.meta.url)), 'no-browser-fallback');
let client, transport, closed = false;
let intentionalTransportClose = false, unexpectedBridgeExit = false, cleanupUnverified = false;
let browserCleanupFailure = '';
let sessionProject = '', sessionURL = '', proxyURL = '', cdpPort = 0;
let sessionStartedAt = '', lastActivityAt = '', lastSuccessfulInspection = '';
let mcpPID = 0, browserPID = 0, browserTargetID = '', browserVersion = '', browserStartedAt = '';
let browserProfilePath = '';
const say = (o) => process.stdout.write(JSON.stringify(o) + '\n');
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

function decode(result) {
  if (result?.isError) throw new Error((result.content ?? []).map(x => x.text ?? '').join('\n'));
  const text = (result?.content ?? []).filter(x => x.type === 'text').map(x => x.text).join('\n');
  try { return JSON.parse(text); } catch { return { text }; }
}
async function call(name, args = {}) {
  if (!client) throw new Error('Inspector session is not running');
  lastActivityAt = new Date().toISOString();
  return decode(await client.callTool({ name, arguments: args }));
}
async function localJSON(url, timeoutMs = 700) {
  const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs), redirect: 'error' });
  if (!response.ok) throw new Error(`Local inspector endpoint returned HTTP ${response.status}`);
  return response.json();
}
async function verifyProxyEndpoint(url) {
  const endpoint = new URL(url);
  if (!['localhost', '127.0.0.1'].includes(endpoint.hostname) || !endpoint.port) throw new Error('Inspector proxy identity is not a valid loopback URL');
  const response = await fetch(endpoint, { signal: AbortSignal.timeout(700), redirect: 'error' });
  await response.body?.cancel();
}
function processTable() {
  const raw = execFileSync('/bin/ps', ['-axo', 'pid=,ppid=,stat=,lstart=,command='], { encoding: 'utf8', timeout: 5000 });
  return raw.split('\n').map(line => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\S+)\s+(.{24})\s+(.*)$/);
    return match ? { pid: Number(match[1]), ppid: Number(match[2]), stat: match[3], startedAt: match[4].trim(), command: match[5] } : null;
  }).filter(Boolean);
}
function findBrowserPID(port) {
  const match = processTable().find(item => item.ppid === mcpPID
    && item.command.startsWith(chromePath)
    && item.command.includes(`--remote-debugging-port=${port}`)
    && /--user-data-dir=\/(?:private\/)?var\/folders\//.test(item.command)
    && item.command.includes('puppeteer_dev_chrome_profile-'));
  if (!match) return null;
  const profile = match.command.match(/--user-data-dir=(\S+)/)?.[1] ?? '';
  const identity = processTable().find(item => item.pid === match.pid);
  return { pid: match.pid, profile, startedAt: identity?.startedAt ?? '' };
}
async function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}
async function verifyTemporaryDirectory() {
  let probe;
  try {
    probe = await mkdtemp(path.join(os.tmpdir(), 'dex3js-inspector-preflight-'));
    await rm(probe, { recursive: true, force: true });
  } catch (error) {
    if (probe) await rm(probe, { recursive: true, force: true }).catch(() => {});
    throw new Error(`Inspector startup stopped safely because TMPDIR is missing, malformed, or not writable (${error.code ?? 'temporary storage error'}). Correct the temporary-directory setting, then reconnect.`);
  }
}
async function browserSnapshot() {
  if (!cdpPort || !proxyURL || !browserTargetID) throw new Error('Managed browser identity is incomplete');
  await verifyProxyEndpoint(proxyURL);
  const [version, targets] = await Promise.all([
    localJSON(`http://127.0.0.1:${cdpPort}/json/version`),
    localJSON(`http://127.0.0.1:${cdpPort}/json/list`)
  ]);
  const target = targets.find(item => item.type === 'page' && item.id === browserTargetID);
  if (!target || target.url !== proxyURL) throw new Error('The DEX-owned inspector tab is no longer available');
  const browser = findBrowserPID(cdpPort);
  if (!browser) throw new Error('The isolated inspector browser process is no longer verifiable');
  browserPID = browser.pid;
  browserProfilePath = browser.profile;
  browserStartedAt = browser.startedAt;
  browserVersion = version.Browser ?? 'Chrome (version unreported)';
  return { browserTargetID, browserVersion, browserPID, proxyURL, cdpPort, sceneBridgeConnected: null };
}
async function waitForManagedBrowser(actualProxyURL, port, timeoutMs = 30000, diagnosticsSource = () => '') {
  const deadline = Date.now() + timeoutMs;
  let lastError = 'Waiting for the isolated browser target';
  while (Date.now() < deadline) {
    const diagnostics = diagnosticsSource();
    if (/Puppeteer failed:.*opening system browser|Opened .* in system browser/i.test(diagnostics)) {
      throw new Error('The DevTools MCP could not start its isolated browser. DEX blocked its default-browser fallback; repair Chrome or temporary storage, then reconnect.');
    }
    try {
      const [version, targets] = await Promise.all([
        localJSON(`http://127.0.0.1:${port}/json/version`),
        localJSON(`http://127.0.0.1:${port}/json/list`)
      ]);
      const target = targets.find(item => item.type === 'page' && item.url === actualProxyURL);
      const browser = findBrowserPID(port);
      if (target && browser && typeof version.Browser === 'string') {
        cdpPort = port; proxyURL = actualProxyURL; browserTargetID = target.id;
        browserPID = browser.pid; browserProfilePath = browser.profile; browserStartedAt = browser.startedAt; browserVersion = version.Browser;
        return;
      }
      lastError = 'The managed browser has no identifiable DEX inspector target yet';
    } catch (error) { lastError = error.message ?? String(error); }
    await delay(200);
  }
  const detail = diagnosticsSource().trim();
  throw new Error(`Could not verify the DEX-owned Chrome target. ${lastError}${detail ? ` MCP startup: ${detail}` : ''}`);
}
async function connect(project, url) {
  if (url && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/?$/.test(url)) throw new Error('Project endpoint must be a local HTTP URL');
  if (cleanupUnverified) {
    const released = await releaseVerifiedBrowser({ pid: browserPID, port: cdpPort, profile: browserProfilePath, startedAt: browserStartedAt });
    if (!released) throw new Error(`The prior DEX-owned browser could not be safely released (${browserCleanupFailure}); no replacement was started. Retry only after reviewing the process identity.`);
    cleanupUnverified = false;
    browserPID = 0; browserProfilePath = ''; browserStartedAt = ''; cdpPort = 0; proxyURL = ''; browserTargetID = ''; browserVersion = '';
    sessionProject = ''; sessionURL = ''; sessionStartedAt = ''; lastActivityAt = ''; lastSuccessfulInspection = '';
  }
  if (client && sessionProject === project && sessionURL === (url ?? '')) {
    try {
      const bridge = await call('bridge_status');
      await browserSnapshot();
      return { ...sessionInfo(bridge), reused: true };
    } catch { /* An invalid bridge or owned browser is replaced as one supervised session. */ }
  }
  if (client && !await disposeMCP()) throw new Error(`The previous inspector session did not release its verified browser resources (${browserCleanupFailure}); DEX will not start a duplicate.`);
  await verifyTemporaryDirectory();
  if (!process.execPath || !await import('node:fs').then(({ existsSync }) => existsSync(chromePath))) {
    throw new Error('Google Chrome is required for the isolated, DEX-owned inspector window. Install Chrome, then reconnect.');
  }
  const { Client } = await import(pathToFileURL(sdk));
  const { StdioClientTransport } = await import(pathToFileURL(stdio));
  const bridgePort = await freePort();
  cdpPort = await freePort();
  while (cdpPort === bridgePort) cdpPort = await freePort();
  const safePath = forceBrowserFallbackForTest
    ? process.env.DEX3JS_TEST_SAFE_PATH
    : (process.env.PATH || '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin');
  if (!safePath) throw new Error('Browser-fallback test requires a test-owned command search path');
  const childEnv = {
    HOME: os.homedir(), PATH: `${browserFallbackGuard}:${safePath}`, TMPDIR: os.tmpdir(),
    BROWSER: '', PUPPETEER: 'true', CDP_PORT: String(cdpPort),
    BRIDGE_PORT: String(bridgePort), CHROME_PATH: forceBrowserFallbackForTest ? process.env.DEX3JS_TEST_CHROME_PATH : chromePath,
    HEADLESS: headless ? 'true' : 'false', DEX3JS_SESSION_ID: sessionID,
    ...(url ? { DEV_URL: url } : {}),
    ...(forceBrowserFallbackForTest && process.env.DEX3JS_TEST_BROWSER_LAUNCH_LOG
      ? { DEX3JS_TEST_BROWSER_LAUNCH_LOG: process.env.DEX3JS_TEST_BROWSER_LAUNCH_LOG }
      : {}),
    ...(forceBrowserFallbackForTest && process.env.DEX3JS_TEST_BROWSER_ATTEMPT_FILE
      ? { DEX3JS_TEST_BROWSER_ATTEMPT_FILE: process.env.DEX3JS_TEST_BROWSER_ATTEMPT_FILE }
      : {}),
    ...(forceBrowserFallbackForTest && process.env.DEX3JS_TEST_BROWSER_ARGS_FILE
      ? { DEX3JS_TEST_BROWSER_ARGS_FILE: process.env.DEX3JS_TEST_BROWSER_ARGS_FILE }
      : {})
  };
  if (forceBrowserFallbackForTest && !childEnv.CHROME_PATH) throw new Error('Browser-fallback test requires a test-owned fake Chrome executable');
  for (const key of ['HTTP_PORT', 'DEV_PORT']) delete childEnv[key];
  transport = new StdioClientTransport({ command: process.execPath, args: [entry], cwd: project,
    env: childEnv, stderr: 'pipe' });
  let diagnostics = '';
  transport.stderr?.on('data', chunk => { diagnostics = (diagnostics + chunk.toString()).slice(-12000); });
  intentionalTransportClose = false; unexpectedBridgeExit = false;
  transport.onclose = () => {
    if (intentionalTransportClose || !sessionProject || unexpectedBridgeExit) return;
    unexpectedBridgeExit = true;
    const session = sessionInfo();
    say({ event: 'disconnected', error: 'The Three.js DevTools MCP bridge process exited unexpectedly. The cached scene remains available; reconnect to verify and replace the owned session.', session: { ...session, sceneBridgeConnected: false, sessionState: 'disconnected' } });
  };
  client = new Client({ name: 'dex3js-native-inspector', version: '2.0.0' }, { capabilities: {} });
  await client.connect(transport);
  mcpPID = transport.pid ?? 0;
  if (!mcpPID) throw new Error('The MCP process did not expose its owned process identifier');
  const listed = await client.listTools();
  const names = new Set(listed.tools.map(x => x.name));
  for (const required of ['bridge_status', 'scene_tree', 'object_details']) if (!names.has(required)) throw new Error(`Installed DevTools MCP is missing ${required}`);
  const proxyPortMatch = diagnostics.match(/Proxy: http:\/\/localhost:(\d+)/);
  if (!proxyPortMatch) throw new Error('The MCP did not report the local inspector proxy port');
  const actualProxy = `http://localhost:${proxyPortMatch[1]}/`;
  await waitForManagedBrowser(actualProxy, cdpPort, 30000, () => diagnostics);
  await verifyProxyEndpoint(actualProxy);
  sessionProject = project; sessionURL = url ?? '';
  sessionStartedAt = new Date().toISOString(); lastActivityAt = sessionStartedAt; lastSuccessfulInspection = '';
  const bridge = await call('bridge_status');
  say({ event: 'ready', tools: [...names], session: sessionInfo(bridge) });
  return { ...sessionInfo(bridge), reused: false };
}
function sessionInfo(bridge = {}) {
  const text = bridge?.text ?? JSON.stringify(bridge);
  const sceneBridgeConnected = bridge?.connected === true || /Bridge: connected/i.test(text);
  return {
    sessionID, projectPath: sessionProject, projectURL: sessionURL,
    browser: 'Google Chrome · isolated DEX profile', browserVersion,
    browserPID, browserTargetID, mcpPID, proxyURL, cdpPort,
    ...(reportBrowserIdentityForTest ? { browserProfilePath, browserStartedAt } : {}),
    sessionStartedAt, lastActivityAt, lastSuccessfulInspection,
    owned: true, sceneBridgeConnected, sessionState: sceneBridgeConnected ? 'connected' : 'awaitingScene'
  };
}
async function cdp(method, params = {}) {
  const version = await localJSON(`http://127.0.0.1:${cdpPort}/json/version`);
  const wsPath = path.join(pkg, 'ws/index.js');
  const wsModule = await import(pathToFileURL(wsPath));
  const WebSocket = wsModule.WebSocket ?? wsModule.default;
  const socket = new WebSocket(version.webSocketDebuggerUrl);
  const id = 1;
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timed out opening the owned Chrome DevTools session')), 1800);
      socket.once('open', () => { clearTimeout(timer); resolve(); });
      socket.once('error', error => { clearTimeout(timer); reject(error); });
    });
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Chrome DevTools ${method} timed out`)), 1800);
      socket.on('message', data => {
        try { const message = JSON.parse(data.toString()); if (message.id === id) { clearTimeout(timer); message.error ? reject(new Error(message.error.message)) : resolve(message.result); } } catch { /* ignore unrelated events */ }
      });
      socket.send(JSON.stringify({ id, method, params }));
    });
    return await response;
  } finally { socket.close(); }
}
async function disposeMCP() {
  if (!client) {
    if (!cleanupUnverified) return true;
    const released = await releaseVerifiedBrowser({ pid: browserPID, port: cdpPort, profile: browserProfilePath, startedAt: browserStartedAt });
    if (released) {
      cleanupUnverified = false; browserPID = 0; browserProfilePath = ''; browserStartedAt = ''; cdpPort = 0;
      sessionProject = ''; sessionURL = ''; sessionStartedAt = ''; lastActivityAt = ''; lastSuccessfulInspection = '';
    }
    return released;
  }
  const active = client;
  const oldBrowser = { pid: browserPID, port: cdpPort, profile: browserProfilePath, startedAt: browserStartedAt };
  const oldProject = sessionProject, oldURL = sessionURL;
  client = undefined;
  intentionalTransportClose = true;
  await active.close().catch(() => {});
  await transport?.close().catch(() => {});
  transport = undefined;
  const browserReleased = await releaseVerifiedBrowser(oldBrowser);
  cleanupUnverified = !browserReleased;
  mcpPID = 0; browserPID = 0; browserTargetID = ''; browserVersion = '';
  browserProfilePath = ''; browserStartedAt = ''; cdpPort = 0; proxyURL = '';
  if (browserReleased) {
    sessionProject = ''; sessionURL = ''; sessionStartedAt = ''; lastActivityAt = ''; lastSuccessfulInspection = '';
  } else {
    browserPID = oldBrowser.pid; browserProfilePath = oldBrowser.profile; browserStartedAt = oldBrowser.startedAt; cdpPort = oldBrowser.port;
    sessionProject = oldProject; sessionURL = oldURL;
  }
  return browserReleased;
}
function ownedBrowserRecord(identity) {
  if (!identity.pid || !identity.port || !identity.profile || !identity.startedAt) return null;
  const item = processTable().find(candidate => candidate.pid === identity.pid);
  if (!item || item.stat.startsWith('Z')) return undefined;
  if (item.startedAt !== identity.startedAt) return null;
  const profile = item.command.match(/--user-data-dir=(\S+)/)?.[1] ?? '';
  const verified = item.command.startsWith(chromePath)
      && item.command.includes(`--remote-debugging-port=${identity.port}`)
      && profile === identity.profile
      && /puppeteer_dev_chrome_profile-/.test(profile);
  return verified ? { ...item, verifiedBrowser: true } : { ...item, terminatingVerifiedProcess: true };
}
async function releaseVerifiedBrowser(identity) {
  browserCleanupFailure = '';
  if (!identity.pid) return true;
  const injectedFailure = process.env.DEX3JS_TEST_CLEANUP_FAILURE_MARKER;
  if (testSessionMutations && injectedFailure && existsSync(injectedFailure)) {
    try { rmSync(injectedFailure); } catch { /* retain the test marker; no resource signal is sent */ }
    browserCleanupFailure = 'test-injected cleanup refusal'; return false;
  }
  let record;
  try { record = ownedBrowserRecord(identity); } catch (error) { browserCleanupFailure = `process verification failed: ${error.message}`; return false; }
  if (record === undefined) return true;
  if (!record) { browserCleanupFailure = 'PID, executable, port, or private profile no longer matches'; return false; }
  try { process.kill(identity.pid, 'SIGTERM'); } catch (error) { if (error.code === 'ESRCH') return true; browserCleanupFailure = `SIGTERM failed: ${error.code ?? error.message}`; return false; }
  const gracefulDeadline = Date.now() + 1800;
  while (Date.now() < gracefulDeadline) {
    try { record = ownedBrowserRecord(identity); } catch (error) { browserCleanupFailure = `process verification failed: ${error.message}`; return false; }
    if (record === undefined) return true;
    if (!record) { browserCleanupFailure = 'process identity changed during SIGTERM cleanup'; return false; }
    if (record.terminatingVerifiedProcess) { await delay(80); continue; }
    await delay(80);
  }
  try { record = ownedBrowserRecord(identity); } catch (error) { browserCleanupFailure = `process verification failed: ${error.message}`; return false; }
  if (record === undefined) return true;
  if (!record) { browserCleanupFailure = 'process identity changed before SIGKILL'; return false; }
  if (record.terminatingVerifiedProcess) { browserCleanupFailure = 'verified browser process changed command while terminating; no further signal was sent'; return false; }
  try { process.kill(identity.pid, 'SIGKILL'); } catch (error) { if (error.code === 'ESRCH') return true; browserCleanupFailure = `SIGKILL failed: ${error.code ?? error.message}`; return false; }
  const killDeadline = Date.now() + 1200;
  while (Date.now() < killDeadline) {
    try { record = ownedBrowserRecord(identity); } catch (error) { browserCleanupFailure = `process verification failed: ${error.message}`; return false; }
    if (record === undefined) return true;
    if (!record) { browserCleanupFailure = 'process identity changed during SIGKILL cleanup'; return false; }
    if (record.terminatingVerifiedProcess) { await delay(80); continue; }
    await delay(80);
  }
  browserCleanupFailure = 'browser remained after verified SIGKILL'; return false;
}
async function shutdown() {
  if (closed) return;
  closed = true;
  await disposeMCP();
  process.exit(0);
}
async function dispatch(message) {
  const { id, op, args = {} } = message;
  try {
    let result;
    if (op === 'connect') result = await connect(args.project, args.url);
    else if (op === 'test-expire-proxy' && testSessionMutations) {
      const endpoint = new URL(args.url);
      if (!['localhost', '127.0.0.1'].includes(endpoint.hostname) || !endpoint.port) throw new Error('Test proxy URL must be loopback');
      proxyURL = endpoint.toString();
      result = { expired: true };
    }
    else if (op === 'close') { await shutdown(); return; }
    else if (op === 'status') {
      const bridge = await call('bridge_status');
      await browserSnapshot();
      result = sessionInfo(bridge);
    } else if (op === 'activate') {
      await browserSnapshot();
      await cdp('Target.activateTarget', { targetId: browserTargetID });
      result = { activated: true, browserTargetID };
    } else if (op === 'tree') {
      await browserSnapshot();
      let status;
      const deadline = Date.now() + 12000;
      do {
        status = await call('bridge_status');
        if (status?.connected === true || /Bridge: connected/i.test(status.text ?? JSON.stringify(status))) break;
        await delay(250);
      } while (Date.now() < deadline);
      if (!(status?.connected === true || /Bridge: connected/i.test(status.text ?? JSON.stringify(status)))) {
        throw new Error('Scene disconnected. The DEX-owned inspector window is open; restart the project browser view, then reconnect.');
      }
      result = await call('scene_tree', { compact: false, depth: 4, maxChildren: 20 });
      lastSuccessfulInspection = new Date().toISOString();
      result = { scene: result, session: sessionInfo(status) };
    } else if (op === 'details') result = await call('object_details', args);
    else if (op === 'preview') result = await call(args.tool, args.params);
    else if (op === 'pending') result = await call('pending_changes');
    else if (op === 'revert') result = await call('revert_changes', args);
    else throw new Error(`Unsupported inspector operation: ${op}`);
    if (op !== 'connect') lastActivityAt = new Date().toISOString();
    say({ id, ok: true, result });
  } catch (error) {
    const detail = error.message ?? String(error);
    say({ id, ok: false, error: detail });
    if (op === 'connect' && client) await disposeMCP();
  }
}
const input = readline.createInterface({ input: process.stdin });
let commandQueue = Promise.resolve();
input.on('line', line => {
  let message;
  try { message = JSON.parse(line); } catch (error) { say({ ok: false, error: error.message }); return; }
  commandQueue = commandQueue.then(() => dispatch(message)).catch(error => say({ id: message.id, ok: false, error: error.message ?? String(error) }));
});
input.on('close', () => { void shutdown(); });
process.on('SIGTERM', () => { void shutdown(); });
process.on('SIGINT', () => { void shutdown(); });
