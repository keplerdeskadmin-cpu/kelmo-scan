// Kepler Messenger server — staff chat (Fly Kawn Travel)
// Node 18+, no npm packages. Run:  node server.js   (port 3100, data in ./data)
'use strict';
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { URL } = require('url');

const PORT = +(process.env.PORT || 3100);
const DATA = path.join(__dirname, 'data');
const FILES = path.join(DATA, 'files');
const MSGS = path.join(DATA, 'messages');
for (const d of [DATA, FILES, MSGS]) fs.mkdirSync(d, { recursive: true });

// ───────── tiny JSON store
function load(name, def) {
  try { return JSON.parse(fs.readFileSync(path.join(DATA, name), 'utf8')); } catch { return def; }
}
const saveTimers = {};
function save(name, obj) {
  clearTimeout(saveTimers[name]);
  saveTimers[name] = setTimeout(() => {
    const f = path.join(DATA, name);
    fs.writeFileSync(f + '.tmp', JSON.stringify(obj, null, 1));
    fs.renameSync(f + '.tmp', f);
  }, 150);
}
const db = {
  users: load('users.json', []),        // {id, phone, name, role, about, disabled, created, lastSeen}
  sessions: load('sessions.json', {}),  // token -> {userId, created, device}
  chats: load('chats.json', []),        // {id, type, name, members, admins, created, createdBy, lastSeq, state:{uid:{read,delivered}}}
  settings: load('settings.json', {}),
};
if (!db.settings.adminKey) {
  db.settings.adminKey = crypto.randomBytes(6).toString('hex');
  save('settings.json', db.settings);
}
if (!db.settings.sms) db.settings.sms = { enabled: false, method: 'GET', url: '', body: '' };
const saveUsers = () => save('users.json', db.users);
const saveSessions = () => save('sessions.json', db.sessions);
const saveChats = () => save('chats.json', db.chats);
const saveSettings = () => save('settings.json', db.settings);

const id = (n = 10) => crypto.randomBytes(n).toString('hex');
const now = () => Date.now();

function normPhone(p) {
  let d = String(p || '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '92' + d.slice(1);
  if (d.length === 10 && d.startsWith('3')) d = '92' + d;
  return d;
}
const userById = (uid) => db.users.find((u) => u.id === uid);
const isApproved = (u) => u && u.approved !== false && !u.disabled;
const publicUser = (u) => u && ({
  id: u.id, phone: u.phone, name: u.name, about: u.about || '', role: u.role,
  online: online.has(u.id), lastSeen: u.lastSeen || 0, disabled: !!u.disabled, approved: u.approved !== false,
});
const appName = () => db.settings.orgName || 'Kepler';

// ───────── messages (jsonl per chat, cached in memory)
const msgCache = new Map(); // chatId -> array
function messagesOf(chatId) {
  if (msgCache.has(chatId)) return msgCache.get(chatId);
  const list = [];
  const f = path.join(MSGS, chatId + '.jsonl');
  if (fs.existsSync(f)) {
    const byId = new Map();
    for (const line of fs.readFileSync(f, 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try {
        const o = JSON.parse(line);
        if (o.op === 'del') { const m = byId.get(o.id); if (m) { m.deleted = true; m.text = ''; m.file = null; } continue; }
        list.push(o); byId.set(o.id, o);
      } catch {}
    }
  }
  msgCache.set(chatId, list);
  return list;
}
function appendLine(chatId, obj) {
  fs.appendFileSync(path.join(MSGS, chatId + '.jsonl'), JSON.stringify(obj) + '\n');
}

function chatView(c, uid) {
  const list = messagesOf(c.id);
  const last = list[list.length - 1] || null;
  const st = (c.state && c.state[uid]) || { read: 0, delivered: 0 };
  let unread = 0;
  for (let i = list.length - 1; i >= 0 && list[i].seq > st.read; i--) if (list[i].from !== uid && !list[i].deleted) unread++;
  return {
    id: c.id, type: c.type, name: c.name || '', members: c.members, admins: c.admins || [],
    created: c.created, lastSeq: c.lastSeq || 0, state: c.state || {}, last, unread,
  };
}
const chatById = (cid) => db.chats.find((c) => c.id === cid);
const isMember = (c, uid) => c && c.members.includes(uid);

// ───────── realtime (WebSocket, RFC 6455, text frames only)
const sockets = new Map(); // userId -> Set(socket)
const online = new Set();
const gateways = new Set(); // sockets of admin phones that send login SMS from their SIM

function wsSend(sock, obj) {
  if (sock.destroyed) return;
  const data = Buffer.from(JSON.stringify(obj));
  let head;
  if (data.length < 126) head = Buffer.from([0x81, data.length]);
  else if (data.length < 65536) { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 126; head.writeUInt16BE(data.length, 2); }
  else { head = Buffer.alloc(10); head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(data.length), 2); }
  try { sock.write(Buffer.concat([head, data])); } catch {}
}
function sendTo(uid, obj) { for (const s of sockets.get(uid) || []) wsSend(s, obj); }
function sendChat(c, obj, except) { for (const m of c.members) if (m !== except) sendTo(m, obj); }
function broadcast(obj) { for (const uid of sockets.keys()) sendTo(uid, obj); }

function setPresence(uid, isOn) {
  const u = userById(uid);
  if (!u) return;
  if (isOn) online.add(uid); else { online.delete(uid); u.lastSeen = now(); saveUsers(); }
  broadcast({ t: 'presence', userId: uid, online: isOn, lastSeen: u.lastSeen || 0 });
}

function markState(c, uid, field, seq) {
  c.state = c.state || {};
  const st = c.state[uid] = c.state[uid] || { read: 0, delivered: 0 };
  let changed = false;
  if (seq > (st[field] || 0)) { st[field] = seq; changed = true; }
  if (field === 'read' && st.read > (st.delivered || 0)) { st.delivered = st.read; changed = true; }
  if (changed) { saveChats(); sendChat(c, { t: 'state', chatId: c.id, userId: uid, read: st.read, delivered: st.delivered }); }
}

function handleWs(uid, sock, msg) {
  let o; try { o = JSON.parse(msg); } catch { return; }
  const c = o.chatId ? chatById(o.chatId) : null;
  if (o.chatId && !isMember(c, uid)) return;
  switch (o.t) {
    case 'send': {
      const kind = ['text', 'image', 'file', 'voice'].includes(o.kind) ? o.kind : 'text';
      const text = String(o.text || '').slice(0, 8000);
      if (kind === 'text' && !text.trim()) return;
      c.lastSeq = (c.lastSeq || 0) + 1;
      const m = {
        id: id(8), seq: c.lastSeq, chatId: c.id, from: uid, kind, text, ts: now(),
        file: o.file && fileMeta(o.file.id) ? { ...fileMeta(o.file.id), dur: o.file.dur || 0 } : null,
        replyTo: o.replyTo || null,
      };
      if (kind !== 'text' && !m.file) return;
      messagesOf(c.id).push(m);
      appendLine(c.id, m);
      markState(c, uid, 'read', m.seq);
      saveChats();
      wsSend(sock, { t: 'ack', tempId: o.tempId, msg: m });
      sendChat(c, { t: 'msg', msg: m }, null);
      // delivered to everyone online right now
      for (const mem of c.members) if (mem !== uid && online.has(mem)) markState(c, mem, 'delivered', m.seq);
      break;
    }
    case 'read': markState(c, uid, 'read', +o.upTo || 0); break;
    case 'delivered': markState(c, uid, 'delivered', +o.upTo || 0); break;
    case 'typing': sendChat(c, { t: 'typing', chatId: c.id, userId: uid }, uid); break;
    case 'delete': {
      const m = messagesOf(c.id).find((x) => x.id === o.msgId);
      if (!m || m.from !== uid || m.deleted) return;
      m.deleted = true; m.text = ''; m.file = null;
      appendLine(c.id, { op: 'del', id: m.id });
      sendChat(c, { t: 'deleted', chatId: c.id, msgId: m.id });
      break;
    }
    case 'ping': wsSend(sock, { t: 'pong' }); break;
    case 'gateway': {
      const u = userById(uid);
      if (o.on && u && u.role === 'admin') gateways.add(sock); else gateways.delete(sock);
      wsSend(sock, { t: 'gateway', on: gateways.has(sock) });
      break;
    }
    case 'smsResult': console.log(`[sms] ${o.ok ? 'sent' : 'FAILED'} via phone gateway (${o.id})`); break;
  }
}

function upgrade(req, sock) {
  const u = new URL(req.url, 'http://x');
  const s = db.sessions[u.searchParams.get('token') || ''];
  const user = s && userById(s.userId);
  const key = req.headers['sec-websocket-key'];
  if (u.pathname !== '/ws' || !isApproved(user) || !key) { sock.end('HTTP/1.1 401 Unauthorized\r\n\r\n'); return; }
  const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
  sock.setNoDelay(true);
  const uid = user.id;
  if (!sockets.has(uid)) sockets.set(uid, new Set());
  const set = sockets.get(uid);
  const first = set.size === 0;
  set.add(sock);
  if (first) setPresence(uid, true);
  // everything sent while offline is now delivered
  for (const c of db.chats) if (isMember(c, uid) && c.lastSeq) markState(c, uid, 'delivered', c.lastSeq);

  let buf = Buffer.alloc(0), frag = [];
  sock.alive = true;
  sock.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (buf.length >= 2) {
      const fin = (buf[0] & 0x80) !== 0, op = buf[0] & 0x0f, masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (len > 1 << 20) { sock.destroy(); return; }
      const mOff = off; if (masked) off += 4;
      if (buf.length < off + len) return;
      let payload = buf.subarray(off, off + len);
      if (masked) { const mask = buf.subarray(mOff, mOff + 4); payload = Buffer.from(payload); for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3]; }
      buf = buf.subarray(off + len);
      sock.alive = true;
      if (op === 8) { try { sock.end(Buffer.from([0x88, 0])); } catch {} return; }
      if (op === 9) { const h = Buffer.from([0x8a, payload.length]); try { sock.write(Buffer.concat([h, payload])); } catch {} continue; }
      if (op === 10) continue;
      if (op === 1 || op === 0) {
        frag.push(payload);
        if (fin) { const text = Buffer.concat(frag).toString('utf8'); frag = []; handleWs(uid, sock, text); }
      }
    }
  });
  const gone = () => {
    gateways.delete(sock);
    if (!set.has(sock)) return;
    set.delete(sock);
    if (set.size === 0) { sockets.delete(uid); setPresence(uid, false); }
  };
  sock.on('close', gone); sock.on('end', gone); sock.on('error', gone);
}
setInterval(() => {
  for (const set of sockets.values()) for (const s of set) {
    if (!s.alive) { s.destroy(); continue; }
    s.alive = false;
    try { s.write(Buffer.from([0x89, 0])); } catch {}
  }
}, 30000);

// ───────── files
function fileMeta(fid) {
  if (!/^[a-f0-9]{20}$/.test(String(fid || ''))) return null;
  try { return JSON.parse(fs.readFileSync(path.join(FILES, fid + '.json'), 'utf8')); } catch { return null; }
}

// ───────── OTP + SMS
const otps = new Map(); // phone -> {code, exp, tries}
const otpLog = [];      // for the admin panel when SMS is not set up
function sendSms(phone, text) {
  for (const g of gateways) {
    if (g.destroyed) { gateways.delete(g); continue; }
    wsSend(g, { t: 'sms', id: id(4), phone, text });
    return Promise.resolve(true);
  }
  const sms = db.settings.sms || {};
  if (!sms.enabled || !sms.url) return Promise.resolve(false);
  const fill = (s, enc) => String(s || '').replace(/\{phone\}/g, enc ? encodeURIComponent(phone) : phone)
    .replace(/\{text\}/g, enc ? encodeURIComponent(text) : text);
  return new Promise((resolve) => {
    try {
      const u = new URL(fill(sms.url, true));
      const lib = u.protocol === 'https:' ? https : http;
      const body = sms.method === 'POST' ? fill(sms.body, false) : null;
      const req = lib.request(u, { method: sms.method === 'POST' ? 'POST' : 'GET', timeout: 15000,
        headers: body ? { 'Content-Type': sms.contentType || 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } : {} },
      (res) => { res.resume(); resolve(res.statusCode >= 200 && res.statusCode < 300); });
      req.on('error', () => resolve(false));
      req.on('timeout', () => { req.destroy(); resolve(false); });
      if (body) req.write(body);
      req.end();
    } catch { resolve(false); }
  });
}

// ───────── HTTP helpers
function json(res, code, obj) {
  const b = Buffer.from(JSON.stringify(obj));
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': b.length, 'Access-Control-Allow-Origin': '*' });
  res.end(b);
}
function readBody(req, max = 1 << 20) {
  return new Promise((resolve, reject) => {
    const parts = []; let n = 0;
    req.on('data', (c) => { n += c.length; if (n > max) { reject(new Error('too large')); req.destroy(); } else parts.push(c); });
    req.on('end', () => resolve(Buffer.concat(parts)));
    req.on('error', reject);
  });
}
async function bodyJson(req) { try { return JSON.parse((await readBody(req)).toString('utf8') || '{}'); } catch { return {}; } }
function auth(req) {
  const h = req.headers.authorization || '';
  const tok = h.startsWith('Bearer ') ? h.slice(7) : new URL(req.url, 'http://x').searchParams.get('token');
  const s = db.sessions[tok || ''];
  const u = s && userById(s.userId);
  return u && !u.disabled ? u : null;
}
function isAdminKey(req) {
  const k = req.headers['x-admin-key'] || new URL(req.url, 'http://x').searchParams.get('key');
  return k && k === db.settings.adminKey;
}

// ───────── routes
async function route(req, res) {
  const u = new URL(req.url, 'http://x');
  const p = u.pathname;
  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,DELETE' });
    return res.end();
  }
  if (p === '/' || p === '/admin') {
    const html = fs.readFileSync(path.join(__dirname, 'admin.html'));
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (p === '/api/ping') return json(res, 200, { ok: true, app: 'fkt-messenger', name: appName() });

  // ── login
  if (p === '/api/auth/request' && req.method === 'POST') {
    const b = await bodyJson(req);
    const phone = normPhone(b.phone);
    if (phone.length < 11 || phone.length > 15) return json(res, 400, { error: 'Please type your full mobile number.' });
    const user = db.users.find((x) => x.phone === phone);
    if (user && user.disabled) return json(res, 403, { error: 'This account is turned off. Contact your admin.' });
    if (!user && db.settings.openSignup === false) return json(res, 403, { error: 'This number is not added by the admin.' });
    const last = otps.get(phone);
    if (last && now() - last.sent < 30000) return json(res, 429, { error: 'Please wait 30 seconds before asking again.' });
    const code = String(crypto.randomInt(100000, 1000000));
    otps.set(phone, { code, exp: now() + 10 * 60000, tries: 0, sent: now() });
    const text = `${code} is your ${appName()} Messenger code. Do not share it.`;
    const ok = await sendSms(phone, text);
    otpLog.unshift({ phone, name: user ? user.name : '(new)', code, ts: now(), sms: ok });
    otpLog.length = Math.min(otpLog.length, 30);
    console.log(`[login code] ${user ? user.name : 'new'} ${phone}: ${code}${ok ? ' (SMS sent)' : ' (no SMS — see admin panel)'}`);
    return json(res, 200, { ok: true, via: ok ? 'sms' : 'admin' });
  }
  if (p === '/api/auth/verify' && req.method === 'POST') {
    const b = await bodyJson(req);
    const phone = normPhone(b.phone);
    const o = otps.get(phone);
    if (!o || o.exp < now()) return json(res, 400, { error: 'Code expired. Ask for a new code.' });
    if (++o.tries > 5) { otps.delete(phone); return json(res, 400, { error: 'Too many tries. Ask for a new code.' }); }
    if (String(b.code || '').trim() !== o.code) return json(res, 400, { error: 'Wrong code.' });
    otps.delete(phone);
    let user = db.users.find((x) => x.phone === phone);
    if (user && user.disabled) return json(res, 403, { error: 'Account is turned off.' });
    let isNew = false;
    if (!user) {
      const first = !db.users.some((x) => x.role === 'admin');
      user = { id: id(6), phone, name: String(b.name || '').slice(0, 60), role: first ? 'admin' : 'staff', created: now(),
        approved: first || db.settings.requireApproval === false };
      db.users.push(user); saveUsers();
      isNew = true;
      for (const a of db.users) if (a.role === 'admin' && a.id !== user.id) sendTo(a.id, { t: 'pending', user: publicUser(user) });
    }
    const token = id(24);
    db.sessions[token] = { userId: user.id, created: now(), device: String(b.device || '').slice(0, 80) };
    saveSessions();
    return json(res, 200, { token, user: publicUser(user), isNew });
  }

  // ── admin panel API (x-admin-key)
  if (p.startsWith('/api/admin/')) {
    if (!isAdminKey(req)) return json(res, 401, { error: 'Wrong admin key' });
    if (p === '/api/admin/state') {
      return json(res, 200, {
        orgName: appName(), users: db.users.map(publicUser), otps: otpLog,
        sms: db.settings.sms, chats: db.chats.length, gateways: gateways.size,
        openSignup: db.settings.openSignup !== false, requireApproval: db.settings.requireApproval !== false,
      });
    }
    if (p === '/api/admin/user' && req.method === 'POST') {
      const b = await bodyJson(req);
      const phone = normPhone(b.phone);
      if (!b.name || phone.length < 11) return json(res, 400, { error: 'Name and a full phone number are required.' });
      let user = b.id ? userById(b.id) : db.users.find((x) => x.phone === phone);
      if (b.id && !user) return json(res, 404, { error: 'Not found' });
      if (!user) { user = { id: id(6), created: now() }; db.users.push(user); }
      const dup = db.users.find((x) => x.phone === phone && x.id !== user.id);
      if (dup) return json(res, 400, { error: 'This number already belongs to ' + dup.name });
      Object.assign(user, { phone, name: String(b.name).slice(0, 60), role: b.role === 'admin' ? 'admin' : 'staff', disabled: !!b.disabled,
        approved: b.approved !== false });
      if (user.disabled) for (const [t, s] of Object.entries(db.sessions)) if (s.userId === user.id) delete db.sessions[t];
      saveUsers(); saveSessions();
      broadcast({ t: 'user', user: publicUser(user) });
      return json(res, 200, { user: publicUser(user) });
    }
    if (p === '/api/admin/sms' && req.method === 'POST') {
      const b = await bodyJson(req);
      db.settings.sms = { enabled: !!b.enabled, method: b.method === 'POST' ? 'POST' : 'GET', url: String(b.url || ''),
        body: String(b.body || ''), contentType: String(b.contentType || '') };
      if (b.orgName) db.settings.orgName = String(b.orgName).slice(0, 40);
      if (b.openSignup != null) db.settings.openSignup = !!b.openSignup;
      if (b.requireApproval != null) db.settings.requireApproval = !!b.requireApproval;
      saveSettings();
      return json(res, 200, { ok: true });
    }
    if (p === '/api/admin/sms-test' && req.method === 'POST') {
      const b = await bodyJson(req);
      const ok = await sendSms(normPhone(b.phone), `${appName()} Messenger test SMS`);
      return json(res, 200, { ok });
    }
    return json(res, 404, { error: 'Not found' });
  }

  // ── files (download)
  if (p.startsWith('/files/')) {
    if (!auth(req)) return json(res, 401, { error: 'Login required' });
    const fid = p.slice(7);
    const meta = fileMeta(fid);
    const f = path.join(FILES, fid);
    if (!meta || !fs.existsSync(f)) return json(res, 404, { error: 'Not found' });
    res.writeHead(200, { 'Content-Type': meta.mime || 'application/octet-stream', 'Content-Length': fs.statSync(f).size,
      'Content-Disposition': `inline; filename="${encodeURIComponent(meta.name)}"`, 'Cache-Control': 'private, max-age=31536000' });
    return fs.createReadStream(f).pipe(res);
  }

  // ── everything below needs a login
  let m0;
  const me = auth(req);
  if (!me) return json(res, 401, { error: 'Login required' });

  if (p === '/api/upload' && req.method === 'POST') {
    const fid = id(10);
    const name = decodeURIComponent(String(req.headers['x-filename'] || 'file')).replace(/[\\/]/g, '_').slice(0, 120);
    const mime = String(req.headers['content-type'] || 'application/octet-stream').slice(0, 100);
    const dst = path.join(FILES, fid);
    const out = fs.createWriteStream(dst);
    let size = 0, tooBig = false;
    req.on('data', (c) => { size += c.length; if (size > 60 * 1024 * 1024) { tooBig = true; req.destroy(); } });
    req.pipe(out);
    out.on('finish', () => {
      if (tooBig) { fs.rmSync(dst, { force: true }); return json(res, 413, { error: 'File is larger than 60 MB' }); }
      const meta = { id: fid, name, mime, size, by: me.id, ts: now() };
      fs.writeFileSync(path.join(FILES, fid + '.json'), JSON.stringify(meta));
      json(res, 200, meta);
    });
    out.on('error', () => json(res, 500, { error: 'Could not save file' }));
    return;
  }
  if (p === '/api/me' && req.method === 'GET') return json(res, 200, { user: publicUser(me), orgName: appName() });
  if (p === '/api/me' && req.method === 'POST') {
    const b = await bodyJson(req);
    if (b.name) me.name = String(b.name).slice(0, 60);
    if (b.about != null) me.about = String(b.about).slice(0, 140);
    saveUsers();
    broadcast({ t: 'user', user: publicUser(me) });
    return json(res, 200, { user: publicUser(me) });
  }
  if (p === '/api/logout' && req.method === 'POST') {
    const tok = (req.headers.authorization || '').slice(7);
    delete db.sessions[tok]; saveSessions();
    return json(res, 200, { ok: true });
  }
  if (!isApproved(me)) return json(res, 403, { error: 'Waiting for admin approval', pending: true });

  // ── staff management inside the app (admins)
  if (p === '/api/staff' && req.method === 'GET') {
    if (me.role !== 'admin') return json(res, 403, { error: 'Admins only' });
    return json(res, 200, { users: db.users.map(publicUser), gatewayOnline: gateways.size > 0,
      requireApproval: db.settings.requireApproval !== false, openSignup: db.settings.openSignup !== false });
  }
  if ((m0 = p.match(/^\/api\/staff\/([a-f0-9]+)$/)) && req.method === 'POST') {
    if (me.role !== 'admin') return json(res, 403, { error: 'Admins only' });
    const u2 = userById(m0[1]);
    if (!u2) return json(res, 404, { error: 'Not found' });
    const b = await bodyJson(req);
    if (b.approved != null) u2.approved = !!b.approved;
    if (b.disabled != null && u2.id !== me.id) u2.disabled = !!b.disabled;
    if (b.role && u2.id !== me.id) u2.role = b.role === 'admin' ? 'admin' : 'staff';
    if (u2.disabled) for (const [t, s2] of Object.entries(db.sessions)) if (s2.userId === u2.id) delete db.sessions[t];
    saveUsers(); saveSessions();
    broadcast({ t: 'user', user: publicUser(u2) });
    return json(res, 200, { user: publicUser(u2) });
  }
  if (p === '/api/settings' && req.method === 'POST') {
    if (me.role !== 'admin') return json(res, 403, { error: 'Admins only' });
    const b = await bodyJson(req);
    if (b.requireApproval != null) db.settings.requireApproval = !!b.requireApproval;
    if (b.openSignup != null) db.settings.openSignup = !!b.openSignup;
    saveSettings();
    return json(res, 200, { ok: true });
  }
  if (p === '/api/users') return json(res, 200, { users: db.users.filter(isApproved).map(publicUser) });
  if (p === '/api/chats' && req.method === 'GET') {
    const list = db.chats.filter((c) => isMember(c, me.id)).map((c) => chatView(c, me.id));
    list.sort((a, b) => ((b.last && b.last.ts) || b.created) - ((a.last && a.last.ts) || a.created));
    return json(res, 200, { chats: list });
  }
  if (p === '/api/chats/direct' && req.method === 'POST') {
    const b = await bodyJson(req);
    const other = userById(b.userId);
    if (!other || other.id === me.id) return json(res, 400, { error: 'Pick a staff member' });
    let c = db.chats.find((x) => x.type === 'direct' && x.members.length === 2 && x.members.includes(me.id) && x.members.includes(other.id));
    if (!c) {
      c = { id: id(8), type: 'direct', members: [me.id, other.id], admins: [], created: now(), createdBy: me.id, lastSeq: 0, state: {} };
      db.chats.push(c); saveChats();
      sendChat(c, { t: 'chat', chat: chatView(c, other.id) }, me.id);
    }
    return json(res, 200, { chat: chatView(c, me.id) });
  }
  if (p === '/api/chats/group' && req.method === 'POST') {
    const b = await bodyJson(req);
    const name = String(b.name || '').trim().slice(0, 60);
    const members = [...new Set([me.id, ...(b.members || []).filter((x) => userById(x))])];
    if (!name) return json(res, 400, { error: 'Group name is required' });
    if (members.length < 2) return json(res, 400, { error: 'Add at least one member' });
    const c = { id: id(8), type: 'group', name, members, admins: [me.id], created: now(), createdBy: me.id, lastSeq: 0, state: {} };
    db.chats.push(c); saveChats();
    for (const m of members) sendTo(m, { t: 'chat', chat: chatView(c, m) });
    return json(res, 200, { chat: chatView(c, me.id) });
  }
  let m;
  if ((m = p.match(/^\/api\/chats\/([a-f0-9]+)\/messages$/))) {
    const c = chatById(m[1]);
    if (!isMember(c, me.id)) return json(res, 404, { error: 'Not found' });
    const before = +(u.searchParams.get('before') || 0) || Infinity;
    const limit = Math.min(+(u.searchParams.get('limit') || 60), 200);
    const all = messagesOf(c.id).filter((x) => x.seq < before);
    if (c.lastSeq) markState(c, me.id, 'delivered', c.lastSeq);
    return json(res, 200, { messages: all.slice(-limit), more: all.length > limit });
  }
  if ((m = p.match(/^\/api\/chats\/([a-f0-9]+)$/)) && req.method === 'POST') {
    const c = chatById(m[1]);
    if (!isMember(c, me.id) || c.type !== 'group') return json(res, 404, { error: 'Not found' });
    const b = await bodyJson(req);
    const admin = (c.admins || []).includes(me.id) || me.role === 'admin';
    if (b.name) { if (!admin) return json(res, 403, { error: 'Only group admins' }); c.name = String(b.name).slice(0, 60); }
    if (b.add || b.remove || b.makeAdmin) {
      if (!admin) return json(res, 403, { error: 'Only group admins' });
      for (const a of b.add || []) if (userById(a) && !c.members.includes(a)) c.members.push(a);
      for (const r of b.remove || []) { c.members = c.members.filter((x) => x !== r); sendTo(r, { t: 'left', chatId: c.id }); }
      for (const a of b.makeAdmin || []) if (c.members.includes(a) && !c.admins.includes(a)) c.admins.push(a);
    }
    if (b.leave) {
      c.members = c.members.filter((x) => x !== me.id);
      c.admins = (c.admins || []).filter((x) => x !== me.id);
      if (!c.admins.length && c.members.length) c.admins.push(c.members[0]);
      sendTo(me.id, { t: 'left', chatId: c.id });
    }
    saveChats();
    for (const mem of c.members) sendTo(mem, { t: 'chat', chat: chatView(c, mem) });
    return json(res, 200, { chat: chatView(c, me.id) });
  }
  return json(res, 404, { error: 'Not found' });
}

const server = http.createServer((req, res) => {
  route(req, res).catch((e) => { console.error(e); try { json(res, 500, { error: 'Server error' }); } catch {} });
});
server.on('upgrade', upgrade);
server.listen(PORT, () => {
  console.log(`Kepler Messenger server on port ${PORT}`);
  console.log(`Admin panel: http://localhost:${PORT}/admin   admin key: ${db.settings.adminKey}`);
});
