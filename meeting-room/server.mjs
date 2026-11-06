// AI 팀 회의실 (Paseo): reads agents and their timelines from the Paseo daemon and serves a 2D office view.
// No npm dependencies of its own: it borrows the client that ships with the globally installed Paseo CLI.
// Runs inside the paseo container as the paseo user, so PASEO_HOME / PASEO_PASSWORD are already set.
import { createServer } from 'node:http'
import { execFile } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { fileURLToPath, pathToFileURL } from 'node:url'
import path from 'node:path'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const PORT = Number(process.env.MEETING_ROOM_PORT || 6769)
const TOKEN = process.env.MEETING_ROOM_TOKEN || ''
const POLL_MS = Number(process.env.MEETING_ROOM_POLL_MS || 4000)
const MAX_EVENTS = 400

const run = (cmd, args) => new Promise((resolve) => execFile(cmd, args, { timeout: 15000, maxBuffer: 16 * 1024 * 1024 }, (err, out) => resolve(err ? '' : String(out))))

// ---------- Paseo client ----------
let lib = null
async function loadLib() {
  if (lib) return lib
  const root = process.env.PASEO_NODE_MODULES || (await run('npm', ['root', '-g'])).trim()
  const imp = (p) => import(pathToFileURL(path.join(root, '@getpaseo/cli/dist', p)).href)
  const [client, target, logs] = await Promise.all([imp('utils/client.js'), imp('utils/daemon-target.js'), imp('commands/agent/logs.js')])
  lib = { connectToDaemon: client.connectToDaemon, selectDaemonTarget: target.selectDaemonTarget, fetchTimeline: logs.fetchAgentTimelineItems }
  return lib
}

let conn = null
async function client() {
  if (conn) return conn
  const l = await loadLib()
  conn = await l.connectToDaemon({ target: l.selectDaemonTarget({}, process.env) })
  return conn
}
async function drop() { const c = conn; conn = null; try { await c?.close() } catch {} }

// ---------- state ----------
const state = { agents: [], events: [], error: null, at: 0, mode: 'client' }
const seen = new Set() // event ids already recorded
const lastUpdated = new Map() // agentId -> updatedAt we last scanned
const agentInfo = new Map() // agentId -> { goal, say, tool }
let firstScan = true

const clip = (t, n = 1500) => { t = String(t ?? '').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t }
const PASEO_ENVELOPE = /^<paseo-system[^>]*>\n?([\s\S]*?)\n?<\/paseo-system>$/

function push(ev) {
  if (seen.has(ev.id)) return
  seen.add(ev.id)
  state.events.push({ ...ev, at: ev.at || new Date().toISOString(), history: firstScan || undefined })
  if (state.events.length > MAX_EVENTS) state.events.splice(0, state.events.length - MAX_EVENTS)
}

function toolLabel(it) {
  const d = it.detail || {}
  const what = d.filePath || d.command || d.path || d.query || d.url || d.label || d.text || it.metadata?.title || ''
  return clip(`${it.name}${what ? ' – ' + String(what).replace(/\s+/g, ' ') : ''}`, 140)
}

function scanTimeline(agent, items) {
  const info = agentInfo.get(agent.id) || {}
  const running = agent.status === 'running'
  const lastAssistant = items.map((x) => x.type).lastIndexOf('assistant_message')
  items.forEach((it, i) => {
    const base = `${agent.id}:`
    if (it.type === 'user_message') {
      const text = String(it.text || '').replace(PASEO_ENVELOPE, '$1')
      if (!info.goal) info.goal = clip(text, 400)
      push({ id: base + (it.messageId || 'u' + i), kind: 'user', from: 'owner', to: agent.id, text: clip(text) })
    } else if (it.type === 'tool_call' && it.agentMessage) {
      const m = it.agentMessage
      const kind = m.event === 'message' ? 'msg' : 'notify'
      if (!info.goal && kind === 'msg') info.goal = clip(m.text, 400)
      push({ id: base + it.callId, kind, event: m.event, from: m.sender?.id || 'unknown', fromTitle: m.sender?.title, to: agent.id, text: clip(m.text) })
    } else if (it.type === 'assistant_message') {
      info.say = clip(it.text, 600)
      // While a turn is running the last message is still streaming: record it once it is final.
      if (running && i === lastAssistant) return
      push({ id: base + (it.messageId || 'a' + i), kind: 'say', from: agent.id, text: clip(it.text) })
    } else if (it.type === 'tool_call' && it.name !== 'heartbeat') {
      if (it.status === 'running') info.tool = toolLabel(it)
    } else if (it.type === 'error') {
      push({ id: base + 'e' + i, kind: 'error', from: agent.id, text: clip(it.message, 400) })
    }
  })
  const lastTool = [...items].reverse().find((x) => x.type === 'tool_call' && !x.agentMessage)
  info.tool = running && lastTool?.status === 'running' ? toolLabel(lastTool) : null
  agentInfo.set(agent.id, info)
}

function summarize(a) {
  const info = agentInfo.get(a.id) || {}
  return {
    id: a.id,
    title: a.title || '',
    provider: a.provider,
    model: a.runtimeInfo?.model || a.model || null,
    status: a.status, // initializing | idle | running | error | closed
    attention: a.requiresAttention ? a.attentionReason : null, // finished | error | permission
    permissions: (a.pendingPermissions || []).length,
    parentId: a.labels?.['paseo.parent-agent-id'] || null,
    workspaceId: a.workspaceId || null,
    cwd: a.cwd,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
    lastError: a.lastError || null,
    goal: info.goal || null,
    say: info.say || null,
    tool: info.tool || null
  }
}

async function pollClient() {
  const c = await client()
  const res = await c.fetchAgents({ filter: { includeBackground: true } })
  const agents = (res.entries || []).map((e) => e.agent).filter((a) => !a.archivedAt && !a.internal)
  for (const a of agents) {
    if (lastUpdated.get(a.id) === a.updatedAt && a.status !== 'running') continue
    try {
      const items = await lib.fetchTimeline(c, a.id, { timeoutMs: 10000 })
      scanTimeline(a, items || [])
    } catch {} // e.g. a provider that can't resume an old session: don't retry until the agent changes
    lastUpdated.set(a.id, a.updatedAt)
  }
  state.agents = agents.map(summarize)
}

// Fallback when the client library can't be loaded (e.g. a future Paseo moved it): status only.
async function pollCli() {
  const out = await run(process.env.PASEO_CLI || 'paseo', ['ls', '-g', '--json'])
  const rows = JSON.parse(out || '[]')
  if (!Array.isArray(rows)) throw new Error(rows?.error?.message || 'paseo ls failed')
  state.agents = rows.map((r) => ({ id: r.id, title: r.name === '-' ? '' : r.name, provider: String(r.provider).split('/')[0], status: r.status, cwd: r.cwd, workspaceId: r.cwd }))
}

let polling = false
async function poll() {
  if (polling) return
  polling = true
  try {
    if (state.mode === 'client') {
      try { await pollClient() } catch (e) {
        await drop()
        if (!lib) { state.mode = 'cli'; console.error('[meeting-room] Paseo client unavailable, using `paseo ls`:', e?.message) }
        throw e
      }
    } else await pollCli()
    state.error = null
    firstScan = false
  } catch (e) {
    state.error = String(e?.message || e).slice(0, 300)
  } finally {
    state.at = Date.now()
    polling = false
  }
}

async function loadRoles() {
  try {
    return JSON.parse(await readFile(process.env.MEETING_ROOM_ROLES || path.join(DIR, 'roles.json'), 'utf8'))
  } catch {
    return { roles: [] }
  }
}

function send(res, code, body, type = 'application/json; charset=utf-8') {
  res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store' })
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body))
}

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  if (TOKEN && url.searchParams.get('token') !== TOKEN) return send(res, 401, { error: 'token required' })
  try {
    if (url.pathname === '/' || url.pathname === '/index.html') {
      return send(res, 200, await readFile(path.join(DIR, 'public', 'index.html')), 'text/html; charset=utf-8')
    }
    if (url.pathname === '/api/roles') return send(res, 200, await loadRoles())
    if (url.pathname === '/api/live') {
      if (Date.now() - state.at > POLL_MS * 3) await poll()
      return send(res, 200, state)
    }
    if (url.pathname === '/healthz') return send(res, 200, { ok: true, mode: state.mode, error: state.error })
    send(res, 404, { error: 'not found' })
  } catch (e) {
    send(res, 500, { error: String(e?.message || e) })
  }
}).listen(PORT, '0.0.0.0', () => console.log(`[meeting-room] http://0.0.0.0:${PORT}`))

poll()
setInterval(poll, POLL_MS)
