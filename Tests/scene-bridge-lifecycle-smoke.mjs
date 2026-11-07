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
assert.match(nativeSource, /if sceneProcess != nil \{\s*refreshScene\(\)\s*return\s*\}/, 'repeat inspect must refresh the live session instead of reconnecting');
assert.match(nativeSource, /\.disabled\(store\.inspecting \|\| store\.sceneConnected \|\| store\.selected == nil\)/, 'the Connect action must not remain active for an existing session');
const child = spawn(process.execPath, [helper], { cwd: root, stdio: ['pipe', 'pipe', 'pipe'] });
let diagnostics = '';
let nextId = 0;
const pending = new Map();
child.stderr.setEncoding('utf8');
child.stderr.on('data', (chunk) => { diagnostics += chunk; });
createInterface({ input: child.stdout }).on('line', (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message.event === 'ready') return;
  const resolve = pending.get(message.id);
  if (resolve) { pending.delete(message.id); resolve(message); }
});

function request(op, args) {
  const id = ++nextId;
  const response = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timed out waiting for ${op}`)); }, 12_000);
    pending.set(id, (message) => { clearTimeout(timer); resolve(message); });
  });
  child.stdin.write(`${JSON.stringify({ id, op, args })}\n`);
  return response;
}

function descendants(pid) {
  const result = spawnSync('/bin/ps', ['-axo', 'pid=,ppid=,command='], { encoding: 'utf8' });
  assert.equal(result.status, 0, `ps failed: ${result.stderr}`);
  const processes = result.stdout.split('\n').map((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/);
    return match ? { pid: Number(match[1]), ppid: Number(match[2]), command: match[3] } : null;
  }).filter(Boolean);
  const owned = new Set([pid]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const item of processes) if (owned.has(item.ppid) && !owned.has(item.pid)) { owned.add(item.pid); changed = true; }
  }
  return processes.filter((item) => owned.has(item.pid) && item.pid !== pid);
}

try {
  const args = { project: root, url: 'http://127.0.0.1:1/' };
  const first = await request('connect', args);
  assert.equal(first.ok, true, first.error);
  assert.equal(first.result.reused, false, 'first connect should create the managed MCP session');
  assert.match(first.result.browserURL, /^http:\/\/127\.0\.0\.1:\d+\/$/);
  const initialDescendants = descendants(child.pid);
  const initialServers = initialDescendants.filter((item) => item.command.includes('threejs-devtools-mcp/dist/index.js'));
  assert.equal(initialServers.length, 1, 'one DEX-owned MCP process should serve the inspection session');
  assert.equal(initialDescendants.some((item) => item.command.includes('Google Chrome.app/Contents/MacOS/Google Chrome')), false, 'the adapter must not launch Chrome');

  const second = await request('connect', args);
  assert.equal(second.ok, true, second.error);
  assert.equal(second.result.reused, true, 'repeat connect should reuse the live MCP transport');
  assert.equal(second.result.browserURL, first.result.browserURL, 'repeat connect should keep the same browser URL');
  const repeatedDescendants = descendants(child.pid);
  const repeatedServers = repeatedDescendants.filter((item) => item.command.includes('threejs-devtools-mcp/dist/index.js'));
  assert.deepEqual(repeatedServers.map((item) => item.pid), initialServers.map((item) => item.pid), 'repeat connect must keep the same MCP process');
  assert.equal(repeatedDescendants.some((item) => item.command.includes('Google Chrome.app/Contents/MacOS/Google Chrome')), false, 'no Chrome process may be created on repeat connect');
  assert.doesNotMatch(diagnostics, /Browser launched via puppeteer|Opened .* in system browser/);
  console.log('PASS: repeat scene connect reuses one MCP process, the same local URL, and launches no browser');
} finally {
  if (child.exitCode === null) {
    child.stdin.write('{"op":"close"}\n');
    const exited = Promise.race([once(child, 'exit'), new Promise((resolve) => setTimeout(resolve, 5_000))]);
    await exited;
    if (child.exitCode === null) {
      child.kill('SIGTERM');
      await once(child, 'exit');
    }
  }
}
