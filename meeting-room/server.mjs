// AI 팀 회의실: reads Orca orchestration state through the orca-ide CLI and serves a 2D view.
// No npm dependencies. Runs inside the orca container as the orca user.
import { createServer } from 'node:http'
import { execFile } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const PORT = Number(process.env.MEETING_ROOM_PORT || 6769)
const TOKEN = process.env.MEETING_ROOM_TOKEN || ''
const ORCA = process.env.ORCA_CLI || 'orca-ide'
const POLL_MS = Number(process.env.MEETING_ROOM_POLL_MS || 4000)

function orca(args) {
  return new Promise((resolve) => {
    execFile(ORCA, [...args, '--json'], { timeout: 15000, maxBuffer: 32 * 1024 * 1024 }, (err, stdout) => {
      try {
        const parsed = JSON.parse(stdout)
        resolve(parsed.ok ? parsed.result : { error: parsed.error })
      } catch {
        resolve({ error: { code: 'cli_failed', message: String(err?.message || stdout).slice(0, 300) } })
      }
    })
  })
}

async function loadRoles() {
  try {
    return JSON.parse(await readFile(process.env.MEETING_ROOM_ROLES || path.join(DIR, 'roles.json'), 'utf8'))
  } catch {
    return { roles: [] }
  }
}

let runs = { list: [], at: 0 }
const runCache = new Map() // runId -> { state, at }

async function refreshRuns() {
  const r = await orca(['orchestration', 'run-list', '--limit', '50'])
  if (!r.error) runs = { list: (r.runs || []).filter((x) => !x.legacy), at: Date.now() }
  return runs
}

async function loadRun(runId) {
  const [tasks, workers, inbox] = await Promise.all([
    orca(['orchestration', 'task-list', '--run', runId, '--full']),
    orca(['orchestration', 'worker-list', '--run', runId, '--limit', '100']),
    orca(['orchestration', 'inbox', '--terminal', `run:${runId}`, '--limit', '200', '--full'])
  ])
  // The run mailbox only holds mail addressed to the run; the global inbox has worker-to-worker mail too.
  const all = await orca(['orchestration', 'inbox', '--limit', '300', '--full'])
  const seen = new Set()
  const messages = [...(inbox.messages || []), ...(all.messages || [])]
    .filter((m) => m.run_id === runId && !seen.has(m.id) && seen.add(m.id))
    .sort((a, b) => (a.created_at < b.created_at ? -1 : 1))
  return {
    runId,
    tasks: tasks.tasks || [],
    workers: workers.workers || [],
    messages,
    errors: [tasks.error, workers.error, inbox.error].filter(Boolean),
    at: Date.now()
  }
}

async function getRun(runId) {
  const hit = runCache.get(runId)
  if (hit && Date.now() - hit.at < POLL_MS) return hit
  const state = await loadRun(runId)
  runCache.set(runId, state)
  return state
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
    if (url.pathname === '/api/runs') {
      if (Date.now() - runs.at > 15000) await refreshRuns()
      return send(res, 200, runs)
    }
    if (url.pathname === '/api/run') {
      const id = url.searchParams.get('id') || ''
      if (!/^run_[A-Za-z0-9_]+$/.test(id)) return send(res, 400, { error: 'bad run id' })
      return send(res, 200, await getRun(id))
    }
    if (url.pathname === '/healthz') return send(res, 200, { ok: true })
    send(res, 404, { error: 'not found' })
  } catch (e) {
    send(res, 500, { error: String(e?.message || e) })
  }
}).listen(PORT, '0.0.0.0', () => console.log(`[meeting-room] http://0.0.0.0:${PORT}`))
