import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { mkdtemp, readFile, writeFile, chmod, rm, mkdir } from 'node:fs/promises';
import os from 'node:os';
import net from 'node:net';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const helper = path.join(root, 'Resources/scene-bridge.mjs');
const nativeSource = readFileSync(path.join(root, 'Sources/DEX3js/main.swift'), 'utf8');
const framerSource = readFileSync(path.join(root, 'Sources/DEX3js/SceneOutputFramer.swift'), 'utf8');
assert.match(nativeSource, /init\(\) \{ DEXAppearance\.applyToApplication\(\) \}/, 'the native app must apply AppKit dark Aqua before showing its window');
assert.match(nativeSource, /\.preferredColorScheme\(DEXAppearance\.colorScheme\)/, 'the app root must force SwiftUI dark appearance');
assert.doesNotMatch(nativeSource, /\.preferredColorScheme\(\.light\)/, 'a light appearance must not be forced');
assert.match(nativeSource, /Inspector session manager/, 'the existing dashboard must explain its active inspector session');
assert.match(nativeSource, /store\.reconnectScene\(\)/, 'the dashboard must offer explicit reconnect');
assert.match(nativeSource, /Darwin\.getpgid\(pid\) == pid/, 'session cleanup must verify the DEX-owned process group leader');
assert.match(nativeSource, /launcher\.arguments = \["--new-window", target\.absoluteString\]/, 'Needle must open in a separate Chrome window using the regular user profile');
assert.doesNotMatch(nativeSource, /NSWorkspace\.shared\.open\(\[target\], withApplicationAt: chrome/, 'Needle launch must not be forwarded into an arbitrary automated Chrome profile');
assert.match(framerSource, /maximumLineBytes = 1_048_576/, 'native helper output must have a bounded line size');
assert.match(nativeSource, /sceneFramer\.finish\(\)/, 'unexpected helper termination must classify truncated output');
assert.match(nativeSource, /sceneFramer\.reset\(\); inspecting = false/, 'cancellation must discard partial output');
assert.match(nativeSource, /Live scene hierarchy/, 'the scene hierarchy must have an accessible name');
assert.match(nativeSource, /Selected scene object:/, 'the selected object must be announced accessibly');
assert.match(nativeSource, /Inspector connection status:/, 'connection status must have an explicit assistive-technology label');
assert.match(nativeSource, /supported material and a live scene connection/, 'preview must explain its disabled preconditions');
assert.match(nativeSource, /willTerminateNotification\).*store\.cancelInspection\(\); store\.stop\(\)/, 'DEX intentionally stops its managed project on app exit; reattachment tests must model an externally surviving project separately');
assert.match(nativeSource, /settings\.last-good\.json/, 'app reconstruction must retain the existing last-known-good settings recovery path');
assert.match(nativeSource, /verifiedProjectProcessRecord\(\)/, 'reconstructed project state must be gated by process identity validation');
assert.match(readFileSync(helper, 'utf8'), /no-browser-fallback/, 'the MCP child must resolve system-browser fallbacks through DEX’s refusing shim');
assert.match(readFileSync(helper, 'utf8'), /verifyTemporaryDirectory\(\)/, 'temporary storage must be validated before MCP initialization');

const sessionCount = Number(process.env.DEX_LIFECYCLE_CYCLES || 10);
const chromeBefore = chromeProcessIDs();
const args = { project: root, url: 'http://127.0.0.1:1/' };
let completed = 0;

function processTable() {
  const result = spawnSync('/bin/ps', ['-axo', 'pid=,ppid=,pgid=,command='], { encoding: 'utf8' });
  assert.equal(result.status, 0, `ps failed: ${result.stderr}`);
  return result.stdout.split('\n').map(line => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);
    return match ? { pid: Number(match[1]), ppid: Number(match[2]), pgid: Number(match[3]), command: match[4] } : null;
  }).filter(Boolean);
}
function chromeProcessIDs() {
  return processTable().filter(item => item.command.startsWith('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'))
    .map(item => item.pid).sort((a, b) => a - b);
}
function mcpProcessIDs() {
  return processTable().filter(item => item.command.includes('/threejs-devtools-mcp/dist/index.js'))
    .map(item => item.pid).sort((a, b) => a - b);
}
function descendants(pid) {
  const all = processTable();
  const owned = new Set([pid]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const item of all) if (owned.has(item.ppid) && !owned.has(item.pid)) { owned.add(item.pid); changed = true; }
  }
  return all.filter(item => owned.has(item.pid) && item.pid !== pid);
}
async function waitUntil(predicate, message, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.fail(message);
}
async function expireTestTarget(session) {
  const response = await fetch(`http://127.0.0.1:${session.cdpPort}/json/version`);
  const version = await response.json();
  const wsPath = path.join(process.env.HOME, '.local/share/3d-lab/threejs-devtools-mcp/node_modules/ws/index.js');
  const wsModule = await import(pathToFileURL(wsPath));
  const WebSocket = wsModule.WebSocket ?? wsModule.default;
  const socket = new WebSocket(version.webSocketDebuggerUrl);
  await once(socket, 'open');
  try {
    const result = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Target.closeTarget timed out')), 2000);
      socket.on('message', data => {
        const message = JSON.parse(data.toString());
        if (message.id !== 1) return;
        clearTimeout(timeout);
        if (message.error) reject(new Error(message.error.message));
        else resolve(message.result);
      });
    });
    socket.send(JSON.stringify({ id: 1, method: 'Target.closeTarget', params: { targetId: session.browserTargetID } }));
    const closed = await result;
    assert.equal(closed.success, true, 'the isolated test-owned target must expire successfully');
  } finally { socket.close(); }
}
async function closedLoopbackURL() {
  const server = net.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return `http://127.0.0.1:${port}/`;
}
async function oneShotRequest({ sessionID, op = 'connect', args = {}, env, extraArgs = [] }) {
  const child = spawn(process.execPath, [helper, '--session-id', sessionID, '--headless', ...extraArgs], {
    cwd: root, env, stdio: ['pipe', 'pipe', 'pipe']
  });
  let diagnostics = '';
  let resolveResponse;
  const response = new Promise(resolve => { resolveResponse = resolve; });
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { diagnostics = (diagnostics + chunk).slice(-12000); });
  createInterface({ input: child.stdout }).on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.id === 1) resolveResponse(message);
  });
  child.stdin.write(`${JSON.stringify({ id: 1, op, args })}\n`);
  try {
    const result = await Promise.race([
      response,
      new Promise((_, reject) => setTimeout(() => reject(new Error(`one-shot connect timed out: ${diagnostics}`)), 15000))
    ]);
    return { result, diagnostics };
  } finally {
    if (child.exitCode === null) {
      child.stdin.write('{"op":"close"}\n');
      await Promise.race([once(child, 'exit'), new Promise(resolve => setTimeout(resolve, 8000))]);
      if (child.exitCode === null) child.kill('SIGTERM');
    }
  }
}
async function verifyBrowserFallbackGuard() {
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'dex3js-browser-guard-'));
  const chromeBefore = chromeProcessIDs();
  const mcpBefore = mcpProcessIDs();
  try {
    const marker = path.join(scratch, 'fallback-attempt.log');
    const missingTemp = path.join(scratch, 'missing-temp');
    const malformedTemp = path.join(scratch, 'not-a-directory');
    await writeFile(malformedTemp, 'fixture');
    for (const [label, tmpdir] of [['missing', missingTemp], ['malformed', malformedTemp]]) {
      const invalid = await oneShotRequest({
        sessionID: `invalid-tmp-${label}-${process.pid}`,
        args: { project: root, url: 'http://127.0.0.1:1/' },
        env: { ...process.env, TMPDIR: tmpdir, DEX3JS_TEST_BROWSER_LAUNCH_LOG: marker }
      });
      assert.equal(invalid.result.ok, false, `${label} TMPDIR must fail before MCP startup`);
      assert.match(invalid.result.error, /TMPDIR is missing, malformed, or not writable/);
      assert.deepEqual(mcpProcessIDs(), mcpBefore, `${label} TMPDIR must not start an MCP child`);
      await assert.rejects(readFile(marker), `${label} TMPDIR must not invoke the browser fallback shim`);
    }
    const passive = await oneShotRequest({
      sessionID: `passive-status-${process.pid}`, op: 'status',
      env: { ...process.env, DEX3JS_TEST_BROWSER_LAUNCH_LOG: marker }
    });
    assert.equal(passive.result.ok, false, 'status without a session should report disconnected');
    assert.deepEqual(mcpProcessIDs(), mcpBefore, 'passive status must not start MCP or a browser');
    await assert.rejects(readFile(marker), 'passive status must not invoke the browser fallback shim');

    const fakeChrome = path.join(scratch, 'fake-chrome');
    const safePath = path.join(scratch, 'empty-path');
    await writeFile(fakeChrome, '#!/bin/sh\nexit 73\n', { mode: 0o700 });
    await chmod(fakeChrome, 0o700);
    await mkdir(safePath);
    const failedPuppeteer = await oneShotRequest({
      sessionID: `forced-fallback-${process.pid}`,
      args: { project: root, url: 'http://127.0.0.1:1/' },
      env: {
        ...process.env,
        DEX3JS_TEST_CHROME_PATH: fakeChrome,
        DEX3JS_TEST_SAFE_PATH: safePath,
        DEX3JS_TEST_BROWSER_LAUNCH_LOG: marker
      },
      extraArgs: ['--test-force-browser-fallback']
    });
    assert.equal(failedPuppeteer.result.ok, false, 'Puppeteer failure must stop initialization');
    assert.match(failedPuppeteer.result.error, /DEX blocked its default-browser fallback/);
    assert.match(await readFile(marker, 'utf8'), /http:\/\/localhost:/, 'the exact fallback request must reach only the refusing shim');
    assert.deepEqual(chromeProcessIDs(), chromeBefore, 'the forced Puppeteer failure must not launch any browser process');
    await waitUntil(() => JSON.stringify(mcpProcessIDs()) === JSON.stringify(mcpBefore),
      'the failed MCP initialization must release its test process');
    console.log('PASS: invalid TMPDIR fails before MCP startup; forced Puppeteer failure reaches only the refusing open shim and starts no browser');
  } finally { await rm(scratch, { recursive: true, force: true }); }
}
async function verifyInterruptedInitializationRecovery() {
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'dex3js-interrupted-start-'));
  const browserBefore = chromeProcessIDs();
  const mcpBefore = mcpProcessIDs();
  const marker = path.join(scratch, 'fallback-attempt.log');
  const attemptFile = path.join(scratch, 'launch-attempted');
  const fakeChrome = path.join(scratch, 'chrome-on-second-attempt');
  const safePath = path.join(scratch, 'empty-path');
  await mkdir(safePath);
  await writeFile(fakeChrome, `#!/bin/sh\nif [ ! -f "$DEX3JS_TEST_BROWSER_ATTEMPT_FILE" ]; then : > "$DEX3JS_TEST_BROWSER_ATTEMPT_FILE"; exit 73; fi\nexec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "$@"\n`);
  await chmod(fakeChrome, 0o700);
  const child = spawn(process.execPath, [helper, '--session-id', `recover-init-${process.pid}`, '--headless', '--test-force-browser-fallback'], {
    cwd: root,
    env: { ...process.env, DEX3JS_TEST_CHROME_PATH: fakeChrome, DEX3JS_TEST_SAFE_PATH: safePath,
      DEX3JS_TEST_BROWSER_LAUNCH_LOG: marker, DEX3JS_TEST_BROWSER_ATTEMPT_FILE: attemptFile },
    stdio: ['pipe', 'pipe', 'pipe']
  });
  let diagnostics = '';
  let nextID = 0;
  const pending = new Map();
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { diagnostics = (diagnostics + chunk).slice(-12000); });
  createInterface({ input: child.stdout }).on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.id && pending.has(message.id)) pending.get(message.id)(message);
  });
  function request(op, args = {}) {
    const id = ++nextID;
    const result = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`recovery ${op} timeout: ${diagnostics}`)); }, 30000);
      pending.set(id, value => { clearTimeout(timer); pending.delete(id); resolve(value); });
    });
    child.stdin.write(`${JSON.stringify({ id, op, args })}\n`);
    return result;
  }
  let session;
  try {
    const interrupted = await request('connect', { project: root, url: 'http://127.0.0.1:1/' });
    assert.equal(interrupted.ok, false, `first initialization should fail safely: ${diagnostics}`);
    assert.match(interrupted.error, /DEX blocked its default-browser fallback/);
    assert.match(await readFile(marker, 'utf8'), /http:\/\/localhost:/);
    await waitUntil(() => JSON.stringify(mcpProcessIDs()) === JSON.stringify(mcpBefore), 'partial MCP session was not released after interrupted startup');
    const recovered = await request('connect', { project: root, url: 'http://127.0.0.1:1/' });
    assert.equal(recovered.ok, true, `a subsequent explicit connection should succeed: ${recovered.error ?? diagnostics}`);
    session = recovered.result;
    assert.equal(session.owned, true);
    assert.equal(session.reused, false);
    assert.equal(await fetch(`http://127.0.0.1:${session.cdpPort}/json/list`).then(response => response.status), 200);
  } finally {
    if (child.exitCode === null) {
      child.stdin.write('{"op":"close"}\n');
      await Promise.race([once(child, 'exit'), new Promise(resolve => setTimeout(resolve, 10000))]);
      if (child.exitCode === null) child.kill('SIGTERM');
    }
    if (session) {
      await waitUntil(() => !processTable().some(item => item.pid === session.mcpPID || item.pid === session.browserPID), 'recovered test session did not release its owned processes');
      await assert.rejects(fetch(`http://127.0.0.1:${session.cdpPort}/json/version`, { signal: AbortSignal.timeout(500) }), 'recovered test session left CDP open');
    }
    assert.deepEqual(chromeProcessIDs(), browserBefore, 'interrupted initialization recovery must leave pre-existing browsers unchanged');
    assert.deepEqual(mcpProcessIDs(), mcpBefore, 'interrupted initialization recovery must release its MCP child');
    await rm(scratch, { recursive: true, force: true });
  }
  console.log('PASS: interrupted Puppeteer initialization releases partial MCP/proxy state; a later explicit connection succeeds and cleans up');
}
async function verifyPortCollisionHandling() {
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'dex3js-port-collision-'));
  const original = http.createServer((request, response) => { response.writeHead(200); response.end('owned collision fixture'); });
  const browserBefore = chromeProcessIDs();
  const mcpBefore = mcpProcessIDs();
  let child;
  await new Promise((resolve, reject) => { original.once('error', reject); original.listen(0, '127.0.0.1', resolve); });
  const occupiedPort = original.address().port;
  const emptyPath = path.join(scratch, 'empty-path');
  await mkdir(emptyPath);
  const entry = path.join(process.env.HOME, '.local/share/3d-lab/threejs-devtools-mcp/node_modules/threejs-devtools-mcp/dist/index.js');
  try {
    child = spawn(process.execPath, [entry], {
      cwd: scratch,
      env: { HOME: process.env.HOME, PATH: emptyPath, TMPDIR: os.tmpdir(), BROWSER: 'none', PUPPETEER: 'true',
        HEADLESS: 'true', BRIDGE_PORT: String(occupiedPort), CDP_PORT: '0', DEV_URL: 'http://127.0.0.1:1/' },
      stdio: ['pipe', 'ignore', 'pipe']
    });
    let diagnostics = '';
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', chunk => { diagnostics = (diagnostics + chunk).slice(-8000); });
    await Promise.race([once(child, 'exit'), new Promise((_, reject) => setTimeout(() => reject(new Error(`occupied-port initialization did not stop: ${diagnostics}`)), 8000))]);
    assert.notEqual(child.exitCode, 0, 'MCP initialization must stop on the deliberately occupied bridge port');
    assert.match(diagnostics, /EADDRINUSE/, 'port collision must be reported rather than stealing the occupied listener');
    assert.equal(await fetch(`http://127.0.0.1:${occupiedPort}/`).then(response => response.text()), 'owned collision fixture', 'the pre-existing listener must remain intact');
    assert.deepEqual(mcpProcessIDs(), mcpBefore, 'failed collision initialization must release its MCP process');
    assert.deepEqual(chromeProcessIDs(), browserBefore, 'BROWSER=none collision fixture must not launch a browser');
  } finally {
    if (child?.exitCode === null) {
      const record = processTable().find(item => item.pid === child.pid);
      assert.ok(record && record.command.includes('/threejs-devtools-mcp/dist/index.js'), 'cleanup must target only the verified fixture MCP child');
      child.kill('SIGTERM');
      await Promise.race([once(child, 'exit'), new Promise(resolve => setTimeout(resolve, 5000))]);
      if (child.exitCode === null) child.kill('SIGKILL');
    }
    await new Promise(resolve => original.close(resolve));
    await rm(scratch, { recursive: true, force: true });
  }
  await waitUntil(() => JSON.stringify(mcpProcessIDs()) === JSON.stringify(mcpBefore), 'port-collision fixture left an MCP process');
  assert.deepEqual(chromeProcessIDs(), browserBefore, 'port-collision fixture must preserve all existing browser processes');
  console.log(`PASS: occupied loopback bridge port ${occupiedPort} failed with EADDRINUSE, preserving its owner and launching no browser`);
}
async function oneCycle(index) {
  const sessionID = `phase4-smoke-${process.pid}-${index}-${Date.now()}`;
  const cleanupScratch = index === 7 ? await mkdtemp(path.join(os.tmpdir(), 'dex3js-cleanup-failure-')) : '';
  const cleanupFailureMarker = cleanupScratch ? path.join(cleanupScratch, 'refuse-once') : '';
  const testArgs = index === 5 || index === 7 ? ['--test-session-mutations'] : [];
  const child = spawn(process.execPath, [helper, '--session-id', sessionID, '--headless', ...testArgs], {
    cwd: root,
    env: cleanupScratch ? { ...process.env, DEX3JS_TEST_CLEANUP_FAILURE_MARKER: cleanupFailureMarker } : process.env,
    stdio: ['pipe', 'pipe', 'pipe']
  });
  let diagnostics = '';
  let readyEvent;
  const helperEvents = [];
  let nextId = 0;
  const pending = new Map();
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { diagnostics = (diagnostics + chunk).slice(-12000); });
  createInterface({ input: child.stdout }).on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.event === 'ready') { readyEvent = message; return; }
    if (message.event === 'disconnected') { helperEvents.push(message); return; }
    const resolve = pending.get(message.id);
    if (resolve) { pending.delete(message.id); resolve(message); }
  });
  function request(op, requestArgs = {}) {
    const id = ++nextId;
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timed out waiting for cycle ${index} ${op}. ${diagnostics}`)); }, 40000);
      pending.set(id, message => { clearTimeout(timer); resolve(message); });
    });
    child.stdin.write(`${JSON.stringify({ id, op, args: requestArgs })}\n`);
    return response;
  }
  try {
    const connects = [request('connect', args), request('connect', args), request('connect', args)];
    const [first, concurrentA, concurrentB] = await Promise.all(connects);
    assert.equal(first.ok, true, `cycle ${index}: ${first.error ?? diagnostics}`);
    let session = first.result;
    assert.equal(session.sessionID, sessionID);
    assert.equal(session.owned, true);
    assert.equal(session.reused, false);
    for (const duplicate of [concurrentA, concurrentB]) {
      assert.equal(duplicate.ok, true, `cycle ${index}: concurrent reconnect: ${duplicate.error}`);
      assert.equal(duplicate.result.reused, true, 'concurrent connects must converge on the one healthy session');
      assert.equal(duplicate.result.mcpPID, session.mcpPID);
      assert.equal(duplicate.result.browserPID, session.browserPID);
      assert.equal(duplicate.result.proxyURL, session.proxyURL);
    }
    assert.match(session.proxyURL, /^http:\/\/localhost:\d+\/$/);
    assert.match(session.browser, /isolated DEX profile/);
    assert.ok(session.browserPID > 0 && session.mcpPID > 0);
    assert.ok(session.browserTargetID && session.browserVersion);
    const browserResponse = await fetch(`http://127.0.0.1:${session.cdpPort}/json/list`);
    assert.equal(browserResponse.status, 200);
    const targets = await browserResponse.json();
    assert.equal(targets.filter(target => target.type === 'page').length, 1, 'one isolated session must create one page target');
    assert.equal(targets.find(target => target.type === 'page')?.id, session.browserTargetID);
    assert.equal(targets.find(target => target.type === 'page')?.url, session.proxyURL);
    const listener = spawnSync('/usr/sbin/lsof', ['-nP', '-a', '-iTCP:' + session.cdpPort, '-sTCP:LISTEN'], { encoding: 'utf8' });
    assert.equal(listener.status, 0, `cycle ${index}: could not verify loopback CDP listener: ${listener.stderr}`);
    assert.match(listener.stdout, /127\.0\.0\.1:/, 'Chrome DevTools must listen on loopback');
    assert.doesNotMatch(listener.stdout, /\*:/, 'Chrome DevTools must not listen on a wildcard interface');

    const stable = await request('connect', args);
    assert.equal(stable.ok, true, `cycle ${index}: repeat connect: ${stable.error}`);
    assert.equal(stable.result.reused, true);
    assert.equal(stable.result.sessionID, sessionID);
    assert.equal(stable.result.browserPID, session.browserPID);
    assert.equal(stable.result.browserTargetID, session.browserTargetID);
    assert.equal(stable.result.proxyURL, session.proxyURL);
    const activated = await request('activate');
    assert.equal(activated.ok, true, `cycle ${index}: target activation: ${activated.error}`);
    assert.equal(activated.result.browserTargetID, session.browserTargetID);
    const status = await request('status');
    assert.equal(status.ok, true, `cycle ${index}: status: ${status.error}`);
    assert.equal(status.result.browserPID, session.browserPID);
    assert.equal(descendants(child.pid).filter(item => item.command.startsWith('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')).length, 1);
    if (index === 1) {
      const disconnected = await request('tree');
      assert.equal(disconnected.ok, false, 'an unreachable project scene must report a useful connection failure');
      assert.match(disconnected.error, /Scene disconnected/i);
      const recovered = await request('connect', args);
      assert.equal(recovered.ok, true, `cycle ${index}: failed scene recovery: ${recovered.error}`);
      assert.equal(recovered.result.reused, true, 'a scene failure must reuse the still-valid managed browser target');
      assert.equal(recovered.result.browserTargetID, session.browserTargetID);
    }

    if (index === 2) {
      const stalePort = session.cdpPort;
      await expireTestTarget(session);
      await waitUntil(async () => {
        const response = await fetch(`http://127.0.0.1:${session.cdpPort}/json/list`);
        return !(await response.json()).some(target => target.id === session.browserTargetID);
      }, 'the test-owned target did not actually expire');
      const recovered = await request('connect', args);
      assert.equal(recovered.ok, true, `cycle ${index}: expired target recovery: ${recovered.error ?? diagnostics}`);
      assert.equal(recovered.result.reused, false, 'an expired browser target must be replaced after its owned session closes');
      assert.notEqual(recovered.result.browserTargetID, session.browserTargetID);
      assert.notEqual(recovered.result.cdpPort, stalePort);
      assert.equal(await fetch(`http://127.0.0.1:${recovered.result.cdpPort}/json/list`).then(response => response.status), 200);
      session = recovered.result;
      await assert.rejects(fetch(`http://127.0.0.1:${stalePort}/json/version`, { signal: AbortSignal.timeout(500) }), 'replaced session must release the stale CDP port');
    }

    if (index === 3) {
      const oldPID = session.browserPID;
      process.kill(oldPID, 'SIGKILL'); // This PID is the isolated test-owned headless Chrome process.
      await waitUntil(() => !processTable().some(item => item.pid === oldPID), `cycle ${index}: test-owned browser did not exit`);
      const recovered = await request('connect', args);
      assert.equal(recovered.ok, true, `cycle ${index}: browser crash recovery: ${recovered.error ?? diagnostics}`);
      assert.equal(recovered.result.reused, false, 'a crashed browser must be replaced after its owned session closes');
      assert.notEqual(recovered.result.browserPID, oldPID);
      session = recovered.result;
    }

    if (index === 4) {
      const replaced = await request('connect', { ...args, project: path.join(root, 'Tests') });
      assert.equal(replaced.ok, true, `cycle ${index}: project identity replacement: ${replaced.error ?? diagnostics}`);
      assert.equal(replaced.result.reused, false, 'a session for another project path must not be reused');
      assert.equal(replaced.result.projectPath, path.join(root, 'Tests'));
      session = replaced.result;
    }

    if (index === 5) {
      const oldMCP = session.mcpPID, oldBrowser = session.browserPID, oldCDP = session.cdpPort;
      const invalidated = await request('test-expire-proxy', { url: await closedLoopbackURL() });
      assert.equal(invalidated.ok, true);
      const failedStatus = await request('status');
      assert.equal(failedStatus.ok, false, 'a missing local proxy must invalidate the current session');
      assert.ok(chromeProcessIDs().includes(oldBrowser), 'passive status must not replace or launch a browser');
      const recovered = await request('connect', args);
      assert.equal(recovered.ok, true, `explicit proxy recovery failed: ${recovered.error ?? diagnostics}`);
      assert.equal(recovered.result.reused, false);
      assert.notEqual(recovered.result.mcpPID, oldMCP);
      assert.notEqual(recovered.result.browserPID, oldBrowser);
      session = recovered.result;
      await assert.rejects(fetch(`http://127.0.0.1:${oldCDP}/json/version`, { signal: AbortSignal.timeout(500) }), 'proxy replacement must close the stale CDP endpoint');
    }

    if (index === 6 || index === 7) {
      const before = processTable();
      const mcp = before.find(item => item.pid === session.mcpPID);
      const browser = before.find(item => item.pid === session.browserPID);
      assert.ok(mcp && mcp.ppid === child.pid && mcp.command.includes('/threejs-devtools-mcp/dist/index.js'), 'crash injection must target the verified test-owned MCP child');
      assert.ok(browser && browser.ppid === mcp.pid && browser.command.startsWith('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'), 'browser identity must be verified before bridge crash');
      process.kill(mcp.pid, 'SIGKILL');
      await waitUntil(() => !processTable().some(item => item.pid === mcp.pid), 'test-owned bridge process did not exit');
      await waitUntil(() => helperEvents.some(event => event.event === 'disconnected'), 'helper did not report unexpected bridge termination');
      assert.equal(helperEvents.at(-1).session.sceneBridgeConnected, false, 'crashed bridge must not remain marked connected');
      const staleRequest = await request('status');
      assert.equal(staleRequest.ok, false, 'requests after bridge crash must fail promptly');
      if (index === 7) await writeFile(cleanupFailureMarker, 'refuse exactly once');
      const recovered = await request('connect', args);
      if (index === 7) {
        assert.equal(recovered.ok, false, 'injected cleanup refusal must prevent replacement');
        assert.match(recovered.error, /test-injected cleanup refusal/);
        assert.ok(processTable().some(item => item.pid === browser.pid), 'failed cleanup must preserve the verified resource for recovery');
        const retry = await request('connect', args);
        assert.equal(retry.ok, true, `bounded cleanup retry failed: ${retry.error ?? diagnostics}`);
        assert.notEqual(retry.result.browserPID, browser.pid);
        session = retry.result;
        await waitUntil(() => !processTable().some(item => item.pid === browser.pid), 'verified cleanup retry left the old browser alive');
      } else {
      assert.equal(recovered.ok, true, `crashed bridge recovery failed: ${recovered.error ?? diagnostics}`);
      assert.equal(recovered.result.reused, false);
      session = recovered.result;
      await waitUntil(() => !processTable().some(item => item.pid === browser.pid), 'verified orphaned browser survived bridge crash recovery');
      }
    }

    const exit = once(child, 'exit');
    if (index === sessionCount) child.stdin.end(); // Simulate the native app closing its helper input.
    else child.stdin.write('{"op":"close"}\n');
    await Promise.race([exit, new Promise((_, reject) => setTimeout(() => reject(new Error(`cycle ${index}: managed session did not stop`)), 10000))]);
    await waitUntil(() => !processTable().some(item => item.pid === session.mcpPID || item.pid === session.browserPID), `cycle ${index}: MCP/browser process survived session shutdown`);
    await assert.rejects(fetch(`http://127.0.0.1:${session.cdpPort}/json/version`, { signal: AbortSignal.timeout(500) }), `cycle ${index}: CDP port remained open`);
    assert.equal(processTable().some(item => item.pid === session.browserPID), false, `cycle ${index}: its isolated Chrome process leaked after cleanup`);
    completed++;
  } finally {
    if (child.exitCode === null) {
      child.stdin.write('{"op":"close"}\n');
      await Promise.race([once(child, 'exit'), new Promise(resolve => setTimeout(resolve, 8000))]);
      if (child.exitCode === null) child.kill('SIGTERM');
    }
    if (cleanupScratch) await rm(cleanupScratch, { recursive: true, force: true });
  }
}

await verifyBrowserFallbackGuard();
await verifyPortCollisionHandling();
await verifyInterruptedInitializationRecovery();
for (let index = 1; index <= sessionCount; index++) await oneCycle(index);
const chromeAfter = chromeProcessIDs();
assert.ok(chromeBefore.every(pid => chromeAfter.includes(pid)), 'the test must leave every pre-existing Chrome process alive');
console.log(`PASS: ${completed}/${sessionCount} isolated browser sessions reused one target per session and released MCP, Chrome, CDP, and proxy resources`);
