// Node 22+. Exercises the running main Compose stack with an existing user's JWT.
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const base = process.env.REALTIME_TEST_GATEWAY_URL || 'http://localhost:8080';
const token = process.env.REALTIME_TEST_TOKEN;
if (!token) {
  console.error('Set REALTIME_TEST_TOKEN to a user JWT returned by POST /api/users/login.');
  process.exit(1);
}
let owner;
try {
  owner = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')).sub;
  assert.equal(typeof owner, 'string');
  assert.ok(owner);
} catch {
  console.error('REALTIME_TEST_TOKEN must contain a JWT with a user sub claim.');
  process.exit(1);
}
const compose = ['compose', '-f', 'docker-compose.yml'];
let instances;
try {
  const containers = execFileSync('docker', [...compose, 'ps', '-q', 'guild-service'], { encoding: 'utf8' }).trim().split(/\s+/).filter(Boolean);
  instances = containers.map(container => execFileSync('docker', ['inspect', '--format', '{{.Config.Hostname}}', container], { encoding: 'utf8' }).trim());
  assert.ok(new Set(instances).size >= 2);
  instances = [...new Set(instances)].slice(0, 2);
} catch {
  console.error('Start at least two Guild replicas with docker compose up -d and configure WS_PUBLIC_INSTANCE_URLS.');
  process.exit(1);
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function request(path, body) {
  const response = await fetch(base + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status} for ${path}`);
  return response.json();
}

async function retry(operation) {
  const deadline = Date.now() + 45000;
  let error;
  while (Date.now() < deadline) {
    try { return await operation(); }
    catch (e) { error = e; await sleep(300); }
  }
  throw error;
}

function deadline(promise, timeout = 6000) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('WebSocket event timed out')), timeout);
  })]).finally(() => clearTimeout(timer));
}

async function connect(negotiation) {
  const socket = new WebSocket(negotiation.url);
  const frames = [], readers = [];
  let closed = false;
  const onClose = new Promise(resolve => socket.addEventListener('close', () => {
    closed = true;
    for (const reader of readers.splice(0)) reader.reject(new Error('WebSocket closed'));
    resolve();
  }, { once: true }));
  socket.addEventListener('message', event => {
    const frame = JSON.parse(event.data);
    const reader = readers.shift();
    if (reader) reader.resolve(frame); else frames.push(frame);
  });
  try {
    await deadline(new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', () => reject(new Error('WebSocket handshake failed')), { once: true });
    }));
  } catch (error) { socket.close(); throw error; }
  return {
    send: frame => socket.send(JSON.stringify(frame)),
    read: () => frames.length ? Promise.resolve(frames.shift()) : closed ? Promise.reject(new Error('WebSocket closed'))
      : deadline(new Promise((resolve, reject) => readers.push({ resolve, reject }))),
    closed: () => deadline(onClose),
    close: () => socket.close(),
  };
}

const sockets = [];
try {
  const create = { name: `realtime-${randomUUID()}`, owner_id: owner, event_id: randomUUID() };
  const guild = await retry(() => request('/api/guilds', create));
  async function pair() {
    const results = await Promise.all(instances.map(instance => retry(async () => {
      const negotiation = await request(`/api/realtime/guilds/${guild.guild_id}?instance_id=${instance}`, {});
      assert.equal(negotiation.instance_id, instance);
      const socket = await connect(negotiation);
      sockets.push(socket);
      return { socket, url: new URL(negotiation.url) };
    })));
    assert.notEqual(results[0].url.port, results[1].url.port);
    return results.map(result => result.socket);
  }
  async function exchange(pair, content) {
    pair[0].send({ type: 'send_message', content });
    const [a, b] = await Promise.all(pair.map(socket => socket.read()));
    assert.equal(a.type, 'message'); assert.equal(a.content, content); assert.equal(b.content, content);
    assert.ok(a.event_id); assert.equal(a.event_id, b.event_id); assert.equal(a.message_id, b.message_id);
  }
  let clients = await pair();
  await exchange(clients, 'replica A -> both replicas');
  await exchange([...clients].reverse(), 'replica B -> both replicas');
  assert.equal((await request(`/api/guilds/${guild.guild_id}/messages`)).messages.length, 2);
  console.log('PASS: Gateway selects two distinct public endpoints; messages cross both Guild replicas; PostgreSQL history contains both messages');

  if (process.argv.includes('--check-redis-recovery')) {
    execFileSync('docker', [...compose, 'exec', '-T', 'redis', 'redis-cli', 'CLIENT', 'KILL', 'TYPE', 'pubsub'], { stdio: 'pipe' });
    await Promise.all(clients.map(socket => socket.closed()));
    clients = await pair();
    await exchange(clients, 'after Redis subscription recovery');
    assert.equal((await request(`/api/guilds/${guild.guild_id}/messages`)).messages.length, 3);
    console.log('PASS: Redis subscription gap closes sockets; reconnect restores cross-replica delivery and persisted history');
  }
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exitCode = 1;
} finally {
  for (const socket of sockets) socket.close();
}
