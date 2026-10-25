// Host-route tests for lib/index.js (F-7 result path authority, F-9 route exposure).
//
// Runs the real plugin module against a stub webServer that keeps the registered handlers, then
// talks to them over a real HTTP socket, so the assertions cover the same path the DSH server uses.
// The capture route is only exercised on its rejection branches: a successful POST would spawn the
// native overlay window and take over the desktop. Run: node test/plugin/routes.test.mjs
import http from 'node:http'
import { mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(here, '..', '..')
const mod = await import(new URL('../../lib/index.js', import.meta.url).href)

const ASCII_ONLY = /^[\x20-\x7E]+$/
const candidates = [join(tmpdir(), 'dsh-screenshot-v2'), join(process.env.PUBLIC || 'C:\\Users\\Public', 'dsh-screenshot-v2')]
const RESULT_DIR = candidates.find((p) => ASCII_ONLY.test(p)) || candidates[candidates.length - 1]
const STATE = join(RESULT_DIR, 'dsh-snip-state.json')
const IMAGE = join(RESULT_DIR, 'dsh-snip-last.png')

const routes = new Map()
const fakeCtx = {
  webServer: {
    register(entry) { routes.set(entry.path, entry.handler) },
  },
  effect(fn) { if (typeof fn === 'function') { try { fn() } catch (e) { /* ignore */ } } },
}
mod.apply(fakeCtx)

const checks = []
function check(name, ok, detail) { checks.push({ name, ok: Boolean(ok), detail: detail || '' }) }

const server = http.createServer((req, res) => {
  const handler = routes.get(String(req.url || '').split('?')[0])
  if (!handler) { res.writeHead(404); res.end('no route'); return }
  Promise.resolve(handler(req, res)).catch((e) => { res.writeHead(500); res.end(String(e)) })
})
await new Promise((r) => server.listen(0, '127.0.0.1', r))
const port = server.address().port
const base = 'http://127.0.0.1:' + port

async function get(path, init) {
  const res = await fetch(base + path, init)
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch (e) { json = null }
  return { status: res.status, text, json, headers: res.headers }
}

// --- routes exist ---------------------------------------------------------------------------
check('routes registered', ['/shot/api/capture', '/shot/api/snip', '/shot/api/state', '/shot/api/last', '/shot/api/lang', '/shot/api/version'].every((p) => routes.has(p)), [...routes.keys()].join(' '))

// --- version: no local paths ----------------------------------------------------------------
const version = await get('/shot/api/version')
check('version returns 2.1.0', version.status === 200 && version.json && version.json.version === '2.1.0', version.text)
check('version exposes no path', version.json && !('resultDir' in version.json) && !/[A-Za-z]:\\/.test(version.text), version.text)

// --- last: payload shape, no absolute path ---------------------------------------------------
const snapshot = { state: existsSync(STATE) ? readFileSync(STATE, 'utf8') : null, image: existsSync(IMAGE) ? readFileSync(IMAGE) : null }
mkdirSync(RESULT_DIR, { recursive: true })
writeFileSync(STATE, JSON.stringify({ result: 'ok', at: 111, file: IMAGE }), 'utf8')
writeFileSync(IMAGE, Buffer.from([0x89, 0x50, 0x4e, 0x47]))
const last = await get('/shot/api/last')
const lastKeys = last.json ? Object.keys(last.json).sort().join(',') : ''
check('last returns data', last.status === 200 && last.json && typeof last.json.data === 'string' && last.json.data.length > 0, lastKeys)
check('last keys are mtime/bytes/name/data', lastKeys === 'bytes,data,mtime,name', lastKeys)
check('last carries no absolute path', !/"(path|dir|file)"\s*:/.test(last.text) && !/[A-Za-z]:\\\\/.test(last.text), last.text.slice(0, 120))

// --- state: echoes at/result, hides the path -------------------------------------------------
const state = await get('/shot/api/state')
check('state hides absolute path', state.status === 200 && state.json && !('file' in state.json) && !('dir' in state.json), state.text)
check('state reports ok+at', state.json && state.json.result === 'ok' && state.json.at === 111, state.text)

// --- F-7: a file outside the agreed directory is an error, not a silent fallback -------------
writeFileSync(STATE, JSON.stringify({ result: 'ok', at: 222, file: 'C:\\Other\\place.png' }), 'utf8')
const mismatch = await get('/shot/api/state')
check('state reports directory mismatch', mismatch.json && mismatch.json.result === 'ok' && /mismatch/.test(String(mismatch.json.error || '')), mismatch.text)
const lastMismatch = await get('/shot/api/last')
check('last refuses a foreign path', lastMismatch.json && lastMismatch.json.error && !lastMismatch.json.data, lastMismatch.text)

// --- F-6: a failing session surfaces the native error ---------------------------------------
writeFileSync(STATE, JSON.stringify({ result: 'error', at: 333, error: 'Failed to save screenshot image to disk.' }), 'utf8')
const failed = await get('/shot/api/state')
check('state forwards the native error', failed.json && failed.json.result === 'error' && /Failed to save/.test(String(failed.json.error || '')), failed.text)

// --- restore the operator's real files -------------------------------------------------------
if (snapshot.state === null) { try { rmSync(STATE, { force: true }) } catch (e) { /* ignore */ } } else { writeFileSync(STATE, snapshot.state, 'utf8') }
if (snapshot.image === null) { try { rmSync(IMAGE, { force: true }) } catch (e) { /* ignore */ } } else { writeFileSync(IMAGE, snapshot.image) }

// --- F-9: method / origin / content-type / body-size guards ---------------------------------
const crossOrigin = await get('/shot/api/capture', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: 'http://evil.example' }, body: '{}' })
check('cross-site POST is refused', crossOrigin.status === 403 && /cross-site/.test(String(crossOrigin.json && crossOrigin.json.error)), crossOrigin.text)

const wrongMethod = await get('/shot/api/capture')
check('GET on capture is refused', wrongMethod.status === 405, wrongMethod.text)

const wrongType = await get('/shot/api/capture', { method: 'POST', headers: { 'Content-Type': 'text/plain', Origin: base }, body: '{}' })
check('non-JSON POST is refused', wrongType.status === 415, wrongType.text)

const tooBig = await get('/shot/api/capture', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base }, body: JSON.stringify({ pad: 'x'.repeat(9000) }) })
check('oversized body is refused', tooBig.status === 413, tooBig.text)

const preflight = await fetch(base + '/shot/api/capture', { method: 'OPTIONS', headers: { Origin: base, 'Access-Control-Request-Method': 'POST' } })
check('preflight answered', preflight.status === 204 && preflight.headers.get('access-control-allow-origin') === base, 'status=' + preflight.status)

const sameOriginLang = await get('/shot/api/lang', { headers: { Origin: base } })
check('same-origin GET is allowed', sameOriginLang.status === 200 && sameOriginLang.json !== null, sameOriginLang.text)

server.close()

const failedChecks = checks.filter((c) => !c.ok)
for (const c of checks) console.log((c.ok ? 'PASS ' : 'FAIL ') + c.name + (c.detail ? ' — ' + c.detail : ''))
console.log('')
console.log('routes.test: ' + checks.length + ' checks, ' + failedChecks.length + ' failed')
process.exit(failedChecks.length === 0 ? 0 : 1)
