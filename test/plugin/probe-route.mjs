// Unit test for host probe route /shot/api/probe
// Exercises the hardened security semantics:
// ① Switch file absent -> 404
// ② Switch file present + GET -> 405 with Allow: POST header
// ③ Switch file present + POST valid JSON -> 200 with body strictly { ok: true } (no path)
// ④ Written disk file content === submitted JSON
// ⑤ Oversized body (> MAX_BODY_BYTES) -> 413 and no disk file created
// ⑥ Invalid JSON -> 400 and no disk file created
// Switch and probe files in %TEMP% are created and cleaned up by this test.
import http from 'node:http'
import assert from 'node:assert'
import { readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const mod = await import(new URL('../../lib/index.js', import.meta.url).href)

const routes = new Map()
const fakeCtx = {
  webServer: {
    register(entry) { routes.set(entry.path, entry.handler) },
  },
  effect(fn) { if (typeof fn === 'function') { try { fn() } catch (e) { /* ignore */ } } },
}
mod.apply(fakeCtx)

if (!routes.has('/shot/api/probe')) {
  console.error('[FAIL] /shot/api/probe was not registered in webServer')
  process.exit(1)
}

const server = http.createServer((req, res) => {
  const handler = routes.get(String(req.url || '').split('?')[0])
  if (!handler) { res.writeHead(404); res.end('no route'); return }
  Promise.resolve(handler(req, res)).catch((e) => { res.writeHead(500); res.end(String(e)) })
})

await new Promise((r) => server.listen(0, '127.0.0.1', r))
const port = server.address().port
const base = 'http://127.0.0.1:' + port

const switchPath = join(tmpdir(), 'dsh-shot-debug.on')
const probePath = join(tmpdir(), 'dsh-shot-probe.json')

function cleanupFiles() {
  try { if (existsSync(switchPath)) rmSync(switchPath) } catch (e) {}
  try { if (existsSync(probePath)) rmSync(probePath) } catch (e) {}
}

try {
  cleanupFiles()

  // ---------------------------------------------------------------------------
  // ① 开关文件不存在 → 404
  // ---------------------------------------------------------------------------
  {
    const resPost = await fetch(base + '/shot/api/probe', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ping: 'test' })
    })
    assert.strictEqual(resPost.status, 404, '① POST when debug switch missing must return 404')

    const resGet = await fetch(base + '/shot/api/probe')
    assert.strictEqual(resGet.status, 404, '① GET when debug switch missing must return 404')
    assert.strictEqual(existsSync(probePath), false, '① probe file must not be written when switch missing')
    console.log('[PASS] ① switch absent -> 404 verified')
  }

  // Enable switch for subsequent tests
  writeFileSync(switchPath, '1', 'utf8')

  // ---------------------------------------------------------------------------
  // ② 开关存在 + GET → 405 且响应头含 Allow: POST
  // ---------------------------------------------------------------------------
  {
    const res = await fetch(base + '/shot/api/probe', { method: 'GET' })
    assert.strictEqual(res.status, 405, '② GET when switch present must return 405')
    const allowHeader = res.headers.get('allow')
    assert.ok(allowHeader && allowHeader.toUpperCase().includes('POST'),
      `② 405 response must include Allow header with POST, got: "${allowHeader}"`)
    assert.strictEqual(existsSync(probePath), false, '② GET must not write probe file')
    console.log('[PASS] ② switch present + GET -> 405 with Allow: POST verified')
  }

  // ---------------------------------------------------------------------------
  // ③ 开关存在 + POST 合法 JSON → 200 且 body 只有 {ok:true}（不得含路径字段）
  // ---------------------------------------------------------------------------
  const testPayload = {
    rect: { x: 120, y: 240, w: 32, h: 32 },
    theme: 'dark',
    svg: { stroke: '#8a8f98', present: true }
  }
  {
    const res = await fetch(base + '/shot/api/probe', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(testPayload)
    })
    assert.strictEqual(res.status, 200, '③ POST valid JSON must return 200')
    const body = await res.json()
    assert.deepStrictEqual(body, { ok: true }, '③ response body must strictly be { ok: true }')
    assert.strictEqual('path' in body, false, '③ response body must not contain path property')
    console.log('[PASS] ③ switch present + POST valid JSON -> 200 { ok: true } (no path) verified')
  }

  // ---------------------------------------------------------------------------
  // ④ 落盘文件内容 = 提交的 JSON
  // ---------------------------------------------------------------------------
  {
    assert.strictEqual(existsSync(probePath), true, '④ probe file must exist on disk')
    const rawDisk = readFileSync(probePath, 'utf8')
    const parsedDisk = JSON.parse(rawDisk)
    assert.deepStrictEqual(parsedDisk, testPayload, '④ disk content must match submitted JSON exactly')
    console.log('[PASS] ④ disk content === submitted JSON verified')
  }

  // ---------------------------------------------------------------------------
  // ⑤ 超大 body → 413 且未落盘
  // ---------------------------------------------------------------------------
  {
    try { if (existsSync(probePath)) rmSync(probePath) } catch (e) {}
    const hugePayload = { padding: 'X'.repeat(9 * 1024) } // > 8KB MAX_BODY_BYTES
    const res = await fetch(base + '/shot/api/probe', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(hugePayload)
    })
    assert.strictEqual(res.status, 413, '⑤ oversized body (> 8KB) must return 413')
    assert.strictEqual(existsSync(probePath), false, '⑤ oversized body must not write probe file')
    console.log('[PASS] ⑤ oversized body -> 413 without disk write verified')
  }

  // ---------------------------------------------------------------------------
  // ⑥ 非法 JSON → 400
  // ---------------------------------------------------------------------------
  {
    try { if (existsSync(probePath)) rmSync(probePath) } catch (e) {}
    const res = await fetch(base + '/shot/api/probe', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: 'not-a-valid-json{{{'
    })
    assert.strictEqual(res.status, 400, '⑥ invalid JSON body must return 400')
    assert.strictEqual(existsSync(probePath), false, '⑥ invalid JSON must not write probe file')
    console.log('[PASS] ⑥ invalid JSON -> 400 without disk write verified')
  }

  console.log('[PASS] All 6 probe-route assertions succeeded')
  process.exit(0)
} catch (err) {
  console.error('[FAIL]', err)
  process.exit(1)
} finally {
  server.close()
  cleanupFiles()
}
