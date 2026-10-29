// Node 22+. Exercises only compose.realtime.yml with its development credentials.
import { createHmac, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const base = process.env.REALTIME_TEST_GATEWAY_URL || 'http://localhost:18080';
const secret = process.env.REALTIME_TEST_JWT_SECRET || 'development-user-secret-with-at-least-32-characters';
const owner = randomUUID();
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const unsigned = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: owner, roles: ['user'], exp: Math.floor(Date.now() / 1000) + 300 })}`;
const token = `${unsigned}.${createHmac('sha256', secret).update(unsigned).digest('base64url')}`;
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
    const results = await Promise.all(['guild-a', 'guild-b'].map(instance => retry(async () => {
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
    execFileSync('docker', ['compose', '-f', 'compose.realtime.yml', 'exec', '-T', 'redis', 'redis-cli', 'CLIENT', 'KILL', 'TYPE', 'pubsub'], { stdio: 'pipe' });
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
