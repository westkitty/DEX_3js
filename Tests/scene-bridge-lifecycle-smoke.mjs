import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const helper = path.join(root, 'Resources/scene-bridge.mjs');
const nativeSource = readFileSync(path.join(root, 'Sources/DEX3js/main.swift'), 'utf8');
assert.match(nativeSource, /init\(\) \{ DEXAppearance\.applyToApplication\(\) \}/, 'the native app must apply AppKit dark Aqua before showing its window');
assert.match(nativeSource, /\.preferredColorScheme\(DEXAppearance\.colorScheme\)/, 'the app root must force SwiftUI dark appearance');
assert.doesNotMatch(nativeSource, /\.preferredColorScheme\(\.light\)/, 'a light appearance must not be forced');
assert.match(nativeSource, /Inspector session manager/, 'the existing dashboard must explain its active inspector session');
assert.match(nativeSource, /store\.reconnectScene\(\)/, 'the dashboard must offer explicit reconnect');
assert.match(nativeSource, /Darwin\.getpgid\(pid\) == pid/, 'session cleanup must verify the DEX-owned process group leader');
assert.match(nativeSource, /launcher\.arguments = \["--new-window", target\.absoluteString\]/, 'Needle must open in a separate Chrome window using the regular user profile');
assert.doesNotMatch(nativeSource, /NSWorkspace\.shared\.open\(\[target\], withApplicationAt: chrome/, 'Needle launch must not be forwarded into an arbitrary automated Chrome profile');

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
async function oneCycle(index) {
  const sessionID = `phase4-smoke-${process.pid}-${index}-${Date.now()}`;
  const child = spawn(process.execPath, [helper, '--session-id', sessionID, '--headless'], {
    cwd: root, stdio: ['pipe', 'pipe', 'pipe']
  });
  let diagnostics = '';
  let readyEvent;
  let nextId = 0;
  const pending = new Map();
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { diagnostics = (diagnostics + chunk).slice(-12000); });
  createInterface({ input: child.stdout }).on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.event === 'ready') { readyEvent = message; return; }
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
    const first = await request('connect', args);
    assert.equal(first.ok, true, `cycle ${index}: ${first.error ?? diagnostics}`);
    const session = first.result;
    assert.equal(session.sessionID, sessionID);
    assert.equal(session.owned, true);
    assert.equal(session.reused, false);
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
  }
}

for (let index = 1; index <= sessionCount; index++) await oneCycle(index);
const chromeAfter = chromeProcessIDs();
assert.ok(chromeBefore.every(pid => chromeAfter.includes(pid)), 'the test must leave every pre-existing Chrome process alive');
console.log(`PASS: ${completed}/${sessionCount} isolated browser sessions reused one target per session and released MCP, Chrome, CDP, and proxy resources`);
