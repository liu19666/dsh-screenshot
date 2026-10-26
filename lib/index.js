// dsh-screenshot host half v2: warm native overlay process + the routes the web half uses.
//
// Contract with src/SnipTool.cs (Program.Main):
//   --serve --parent <pid> --out <dir> --client [--show] [--dark|--light] [--lang zh|en]
// Wake-up line on \\.\pipe\dsh-snip-show:
//   show theme=dark|light lang=zh|en client=1 out=<ascii dir>
// The native side answers "ok" and then runs one capture session. Both halves agree on one
// result directory; the native side reports the file it really wrote in dsh-snip-state.json
// and this half reads that field instead of rebuilding the path from its own idea of --out.
import { spawn } from 'node:child_process'
import { connect } from 'node:net'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = fileURLToPath(new URL('.', import.meta.url))
const SNIP_EXE = join(HERE, '..', 'bin', 'SnipTool.exe')
const SNIP_PIPE = '\\\\.\\pipe\\dsh-snip-show'

// F-7: one constant, ASCII-only result directory. The wake-up line travels over an ASCII
// named pipe, so a path outside ASCII could never be echoed consistently; pick a directory
// that is ASCII by construction and fall back to %PUBLIC% only if the temp path is not.
const ASCII_ONLY = /^[\x20-\x7E]+$/
const DIR_CANDIDATES = [
  join(tmpdir(), 'dsh-screenshot-v2'),
  join(process.env.PUBLIC || 'C:\\Users\\Public', 'dsh-screenshot-v2'),
]
const RESULT_DIR = DIR_CANDIDATES.find((p) => ASCII_ONLY.test(p)) || DIR_CANDIDATES[DIR_CANDIDATES.length - 1]
const RESULT_NAME = 'dsh-snip-last.png'
const STATE_NAME = 'dsh-snip-state.json'
const MAX_IMAGE_BYTES = 32 * 1024 * 1024
const MAX_BODY_BYTES = 8 * 1024
const DEBUG_SWITCH_FILE = join(tmpdir(), 'dsh-shot-debug.on')
const PROBE_FILE = join(tmpdir(), 'dsh-shot-probe.json')

export const inject = ['webServer']

function powershellPath() {
  const root = process.env.SystemRoot || 'C:\\Windows'
  return join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
}

function ensureResultDir() {
  try { mkdirSync(RESULT_DIR, { recursive: true }) } catch (e) { /* ignore */ }
}

// DSH records the UI language in the profile; the capture UI follows it so both halves
// never disagree. CommonJS "require" is unavailable here (the package is ESM).
function readProfileLocale() {
  try {
    const home = process.env.DSH_HOME || join(homedir(), '.dsh')
    const profiles = join(home, 'profiles')
    if (!existsSync(profiles)) return null
    for (const name of readdirSync(profiles)) {
      const file = join(profiles, name, 'cordis.patch.yml')
      if (!existsSync(file)) continue
      const text = readFileSync(file, 'utf8')
      const at = text.indexOf('dsh-client-locale')
      if (at < 0) continue
      const m = /preference:\s*"?([A-Za-z-]+)"?/.exec(text.slice(at, at + 400))
      if (m) return m[1]
    }
  } catch (e) { /* ignore */ }
  return null
}

function hostLang() {
  const pref = readProfileLocale()
  if (!pref) return null
  return String(pref).toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

// --- state file (owned by the native side) -------------------------------------------

function readStateFile() {
  try {
    const parsed = JSON.parse(readFileSync(join(RESULT_DIR, STATE_NAME), 'utf8'))
    return {
      at: Number(parsed.at) || 0,
      result: String(parsed.result || ''),
      file: typeof parsed.file === 'string' ? parsed.file : '',
      error: typeof parsed.error === 'string' ? parsed.error : '',
    }
  } catch (e) { return null }
}

function sameDir(a, b) {
  const norm = (p) => String(p).replace(/[\\/]+$/, '').toLowerCase()
  return norm(a) === norm(b)
}

// F-7: the native file path is authoritative. A file outside the agreed directory means the
// two halves disagree about --out; that is surfaced as an error and never papered over by
// reading a guessed file name.
function resultPathFromState(st) {
  if (!st) return { error: 'no capture session yet (state file missing in the agreed result directory)' }
  if (!st.file) return { error: 'capture session state has no file field, so the screenshot cannot be located' }
  const dir = dirname(st.file)
  if (!sameDir(dir, RESULT_DIR)) {
    return { error: 'result directory mismatch: the native side wrote to ' + dir + ' but the host reads ' + RESULT_DIR }
  }
  return { path: st.file }
}

export function apply(ctx) {
  const webServer = ctx.webServer
  if (!webServer) return

  ensureResultDir()
  let warmProc = null

  function pingWarm() {
    return new Promise((resolve) => {
      let settled = false
      let socket
      const finish = (ok) => {
        if (settled) return
        settled = true
        try { if (socket) socket.destroy() } catch (e) { /* ignore */ }
        resolve(ok)
      }
      try {
        socket = connect(SNIP_PIPE)
      } catch (e) {
        resolve(false)
        return
      }
      socket.setTimeout(300)
      socket.once('connect', () => {
        try { socket.write('ping\n') } catch (e) { finish(true); return }
        finish(true)
      })
      socket.once('error', () => finish(false))
      socket.once('timeout', () => finish(false))
    })
  }

  // F-10: only an instance this host spawned, without a window, older than 8s can be wedged;
  // a SnipTool.exe the user started by hand (it owns a window while capturing) is left alone.
  function killWedgedTool() {
    return new Promise((resolve) => {
      const parent = String(process.pid)
      const ps = "$me = " + parent + "; " +
        "Get-CimInstance Win32_Process -Filter \"Name='SnipTool.exe'\" -ErrorAction SilentlyContinue | " +
        "Where-Object { $_.ParentProcessId -eq $me } | " +
        "ForEach-Object { $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue; " +
        "if ($p -and $p.MainWindowHandle -eq 0 -and ((Get-Date) - $p.StartTime).TotalSeconds -gt 8) { " +
        "try { $p.Kill() } catch { } } }"
      let child
      try {
        child = spawn(powershellPath(), ['-NoProfile', '-NonInteractive', '-Command', ps],
          { stdio: 'ignore', windowsHide: true })
      } catch (e) { resolve(); return }
      const timer = setTimeout(() => { try { child.kill() } catch (e) { /* ignore */ } resolve() }, 2500)
      child.once('exit', () => { clearTimeout(timer); resolve() })
      child.once('error', () => { clearTimeout(timer); resolve() })
    })
  }

  // Wake-up line understood by Program.Main's serve loop:
  //   show theme=dark|light lang=zh|en hide=1|0 client=1 out=<ascii dir>
  // "client=1" means DSH pastes the PNG itself, so the overlay must not synthesize Ctrl+V.
  // "hide=1" asks the overlay to conceal DSH for this session (right-click entry); "hide=0"
  // leaves DSH on screen (left-click entry). Every wake line carries the flag explicitly, so a
  // stale state can never leak from one session into the next.
  function wakeWarm(theme, lang, hide) {
    return new Promise((resolve) => {
      let settled = false
      let socket
      const finish = (ok) => {
        if (settled) return
        settled = true
        try { if (socket) socket.destroy() } catch (e) { /* ignore */ }
        resolve(ok)
      }
      try {
        socket = connect(SNIP_PIPE)
      } catch (e) {
        resolve(false)
        return
      }
      socket.setTimeout(400)
      let reply = ''
      socket.once('connect', () => {
        const parts = ['show']
        if (theme) parts.push(theme === '--dark' ? 'theme=dark' : 'theme=light')
        if (lang) parts.push('lang=' + lang)
        parts.push(hide ? 'hide=1' : 'hide=0')
        parts.push('client=1')
        parts.push('out=' + RESULT_DIR)
        try { socket.write(parts.join(' ') + '\n') } catch (e) { finish(false); return }
      })
      socket.on('data', (chunk) => {
        reply += chunk.toString('ascii')
        if (reply.indexOf('ok') === 0) finish(true)
      })
      socket.once('error', () => finish(false))
      socket.once('timeout', () => finish(false))
      socket.once('close', () => finish(false))
    })
  }

  function spawnArgs(extra, hide) {
    const argv = ['--serve']
    if (extra) argv.push('--show')
    argv.push('--parent', String(process.pid), '--out', RESULT_DIR, '--client')
    if (extra) argv.push(hide ? '--hide' : '--no-hide')
    return argv
  }

  async function ensureWarm() {
    if (await pingWarm()) return
    if (!existsSync(SNIP_EXE)) return
    ensureResultDir()
    try {
      warmProc = spawn(SNIP_EXE, spawnArgs(false),
        { stdio: 'ignore', windowsHide: true, detached: true })
      warmProc.unref()
    } catch (e) { /* ignore */ }
  }

  const warmFirst = setTimeout(() => { void ensureWarm() }, 300)
  const warmTick = setInterval(() => { void ensureWarm() }, 45000)

  if (typeof ctx.effect === 'function') {
    ctx.effect(() => () => {
      try { clearTimeout(warmFirst) } catch (e) { /* ignore */ }
      try { clearInterval(warmTick) } catch (e) { /* ignore */ }
      try { if (warmProc) warmProc.kill() } catch (e) { /* ignore */ }
    }, 'screenshot helper v2')
  }

  // --- routes ------------------------------------------------------------------------
  // F-9: the routes are reachable from any page the browser has open, so mutating calls are
  // POST-only, cross-site origins are refused, request bodies are capped, and responses never
  // carry an absolute path (the web half has no use for one).

  function corsHeaders(req) {
    const origin = req.headers.origin
    if (!origin) return null
    return {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '600',
      Vary: 'Origin',
    }
  }

  function originAllowed(req) {
    const origin = req.headers.origin
    if (!origin) return true
    let parsed
    try { parsed = new URL(origin) } catch (e) { return false }
    const host = String(req.headers.host || '')
    if (parsed.host && parsed.host === host) return true
    return parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost' || parsed.hostname === '::1'
  }

  function sendJson(res, code, payload, cors, extraHeaders) {
    const headers = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }
    if (extraHeaders) Object.assign(headers, extraHeaders)
    if (cors) for (const key of Object.keys(cors)) headers[key] = cors[key]
    res.writeHead(code, headers)
    res.end(JSON.stringify(payload))
  }

  async function readJson(req) {
    let size = 0
    let body = ''
    for await (const chunk of req) {
      size += chunk.length
      if (size > MAX_BODY_BYTES) {
        const err = new Error('request body too large')
        err.statusCode = 413
        throw err
      }
      body += chunk
    }
    if (!body || !body.trim()) return {}
    try {
      return JSON.parse(body)
    } catch (e) {
      const err = new Error('invalid json in request body')
      err.statusCode = 400
      throw err
    }
  }

  function route(name, handler, options) {
    const opts = options || {}
    const methods = opts.methods || ['GET']
    webServer.register({
      kind: 'exact',
      path: '/shot/api/' + name,
      handler: async (req, res) => {
        const cors = corsHeaders(req)
        const method = String(req.method || 'GET').toUpperCase()
        if (typeof opts.enabled === 'function' && !opts.enabled(req)) {
          sendJson(res, 404, { error: 'not found' }, cors)
          return
        }
        if (method === 'OPTIONS') {
          res.writeHead(204, cors || {})
          res.end()
          return
        }
        if (!originAllowed(req)) {
          sendJson(res, 403, { error: 'request rejected: cross-site origin' }, cors)
          return
        }
        if (methods.indexOf(method) < 0) {
          sendJson(res, 405, { error: 'method ' + method + ' is not allowed here' }, cors, { Allow: methods.join(', ') })
          return
        }
        if (method === 'POST') {
          const type = String(req.headers['content-type'] || '')
          if (type && type.indexOf('application/json') < 0) {
            sendJson(res, 415, { error: 'content-type must be application/json' }, cors)
            return
          }
        }
        let args = {}
        try {
          args = await readJson(req)
        } catch (e) {
          const status = (e && e.statusCode) || 413
          sendJson(res, status, { error: (e && e.message) || 'request body error' }, cors)
          return
        }
        let result
        try {
          result = await handler(args, req)
        } catch (error) {
          result = { error: String((error && error.message) || error).slice(0, 500) }
        }
        if (res.writableEnded || res.headersSent) return
        const status = (result && typeof result._status === 'number') ? result._status : 200
        if (result && '_status' in result) delete result._status
        sendJson(res, status, result, cors)
      },
    })
  }

  async function triggerSnip(args) {
    const theme = args && args.theme === 'dark' ? '--dark' : args && args.theme === 'light' ? '--light' : null
    const pageLang = args && args.lang === 'en' ? 'en' : args && args.lang === 'zh' ? 'zh' : null
    const lang = hostLang() || pageLang || 'zh'
    const hide = !!(args && args.hide)

    if (!existsSync(SNIP_EXE)) {
      return {
        error: lang === 'zh'
          ? '截图工具未就绪（找不到 bin/SnipTool.exe）'
          : 'Screenshot tool not ready (bin/SnipTool.exe missing)'
      }
    }

    ensureResultDir()
    try {
      for (let attempt = 0; attempt < 4; attempt += 1) {
        if (await wakeWarm(theme, lang, hide)) return { ok: true }
        await new Promise((r) => setTimeout(r, 90))
      }
      await killWedgedTool()
      const argv = spawnArgs(true, hide)
      if (theme) argv.push(theme)
      if (lang) argv.push('--lang', lang)
      const child = spawn(SNIP_EXE, argv, { stdio: 'ignore', windowsHide: false, detached: true })
      child.unref()
    } catch (error) {
      return {
        error: lang === 'zh'
          ? '启动截图工具失败：' + String((error && error.message) || error).slice(0, 300)
          : 'Failed to start screenshot tool: ' + String((error && error.message) || error).slice(0, 300)
      }
    }
    return { ok: true }
  }

  route('capture', async (args) => {
    return await triggerSnip(args)
  }, { methods: ['POST'] })

  // Backwards-compatible alias for clients built before the route was renamed.
  route('snip', async (args) => {
    return await triggerSnip(args)
  }, { methods: ['POST'] })

  // Session outcome. "at" only has to change between sessions; "result" is ok/cancel/error and
  // "error" carries the native failure text so the web half can show it instead of guessing.
  route('state', async () => {
    const st = readStateFile()
    if (!st) return { at: 0, result: '' }
    const payload = { at: st.at, result: st.result }
    if (st.error) payload.error = st.error
    if (st.result === 'ok') {
      const loc = resultPathFromState(st)
      if (loc.error) payload.error = loc.error
    }
    return payload
  })

  // The captured PNG, base64 encoded. No path fields: the client only needs the bytes.
  route('last', async () => {
    const st = readStateFile()
    if (!st) return { mtime: 0 }
    if (st.result === 'error') return { mtime: 0, error: st.error || 'the native side reported an error' }
    if (st.result !== 'ok') return { mtime: 0 }
    const loc = resultPathFromState(st)
    if (loc.error) return { mtime: 0, error: loc.error }
    let info
    try {
      info = statSync(loc.path)
    } catch (e) {
      return { mtime: 0, error: 'the native side reported a screenshot that is not on disk' }
    }
    if (info.size > MAX_IMAGE_BYTES) {
      return { mtime: info.mtimeMs, error: 'screenshot is larger than ' + MAX_IMAGE_BYTES + ' bytes' }
    }
    let data
    try {
      data = readFileSync(loc.path)
    } catch (e) {
      return { mtime: 0, error: 'the screenshot file could not be read' }
    }
    return { mtime: info.mtimeMs, bytes: data.length, name: RESULT_NAME, data: data.toString('base64') }
  })

  route('lang', async () => ({ lang: hostLang() || 'zh' }))

  route('version', async () => ({ version: '2.1.1' }))

  // Debug probe route for verifying UI element state, CSS styling, and SVG rendering in the browser.
  // Disabled by default: only active when %TEMP%\dsh-shot-debug.on exists.
  route('probe', async (args) => {
    try {
      writeFileSync(PROBE_FILE, JSON.stringify(args || {}, null, 2), 'utf8')
    } catch (e) {
      return { _status: 500, ok: false, error: String((e && e.message) || e) }
    }
    return { ok: true }
  }, {
    methods: ['POST'],
    enabled: () => existsSync(DEBUG_SWITCH_FILE),
  })
}
