#!/usr/bin/env node
// tools/plugin-smoke.mjs — stub-load smoke test for the DSH screenshot plugin.
//
// Usage:
//   node tools/plugin-smoke.mjs [--root <repo>] [--json <file>] [--quiet]
//
// The plugin has two halves (see docs/INTERFACES.md):
//   lib/index.js   host half, an ES module consumed by the DSH profile loader
//   lib/client.js  web half, a browser bundle registered through window.__ModuleLoader__
//
// This smoke test never starts DSH and never spawns the native tool. It:
//   1. meta          package.json carries the fields the profile loader reads
//   2. patch         cordis.patch.yml inserts this bundle
//   3. host-syntax   lib/index.js parses (node --check)
//   4. client-syntax lib/client.js parses (node --check)
//   5. host-load     lib/index.js imports and exposes apply()/inject
//   6. client-load   lib/client.js registers with a stub __ModuleLoader__, its factory
//                    runs against a stub React/DOM, and it must ALSO pass
//                    tools/client-contract.mjs: the real Cordis slots contract (declared
//                    inject, effect-style inject(key, callback), single-slot rules). The
//                    stub load alone is exactly what let the broken 2.0.0 bundle ship.
//   7. cli-sync      every flag lib/index.js passes to SnipTool.exe is parsed by
//                    Program.Main, and the host no longer depends on "hide"
//   8. binary        bin/SnipTool.exe exists (informational only)
//
// Statuses per check: pass | warn | pending | fail.
//   pending = the module has not been written yet (missing or still a placeholder).
//   warn    = a check that cannot be decisive in a headless stub (e.g. the host module
//             imports a DSH-internal package that only exists inside a profile).
// Overall status = fail when any check fails, else pending when any check is pending,
// else pass. Exit code: 1 on fail, 0 on pass/pending (pending is reported, not fatal).
//
// The JSON written with --json is read by tools/e2e.ps1.

import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, statSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import vm from 'node:vm'
import { runContract } from './client-contract.mjs'

const args = process.argv.slice(2)
function argValue(name, fallback = null) {
  const i = args.indexOf(name)
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback
}
const quiet = args.includes('--quiet')
const jsonPath = argValue('--json')
const root = resolve(argValue('--root', join(dirname(fileURLToPath(import.meta.url)), '..')))

const checks = []
function addCheck(id, title, status, detail, extra) {
  const c = { id, title, status, detail: detail || '' }
  if (extra) Object.assign(c, extra)
  checks.push(c)
  if (!quiet) {
    const tag = status.toUpperCase().padEnd(7)
    console.log('[' + tag + '] ' + id + ' — ' + title + (detail ? '\n          ' + detail : ''))
  }
  return c
}
function checkFromError(id, title, error, { pendingOnMissing = false } = {}) {
  const message = String((error && error.message) || error)
  if (pendingOnMissing && /ENOENT|no such file/i.test(message)) {
    return addCheck(id, title, 'pending', message)
  }
  return addCheck(id, title, 'fail', message)
}
function readText(path) {
  return readFileSync(path, 'utf8')
}
function statSafe(path) {
  try { return statSync(path) } catch { return null }
}
// Placeholder detection: a module that is only a scaffold must report pending instead of
// failing the whole chain. Keep this deliberately narrow so real code never matches.
const PLACEHOLDER = /not implemented yet|TODO\(plugin-dev\)|IMPLEMENT ME|throw new Error\('stub'\)/i

let packageJson = null
let pkg = null

// --- 1. package.json ---------------------------------------------------------------
const pkgPath = join(root, 'package.json')
try {
  packageJson = readText(pkgPath)
  pkg = JSON.parse(packageJson)
  const problems = []
  if (!pkg.name) problems.push('missing "name"')
  if (!pkg.version) problems.push('missing "version"')
  if (pkg.type !== 'module') problems.push('"type" should be "module" (host half is an ES module)')
  if (!pkg.main && !(pkg.exports && pkg.exports['.'])) problems.push('missing "main" or "exports[\".\"]"')
  const bundlePatch = pkg.dsh && pkg.dsh.bundle && pkg.dsh.bundle.patch
  if (!bundlePatch) problems.push('missing "dsh.bundle.patch" (profile loader needs it)')
  else if (!existsSync(join(root, bundlePatch))) problems.push('dsh.bundle.patch points at a missing file: ' + bundlePatch)
  if (!(pkg.files || []).includes('bin/')) problems.push('"files" should ship bin/ (native exe)')
  if (!(pkg.files || []).includes('lib/')) problems.push('"files" should ship lib/ (plugin halves)')
  if (pkg.os && !pkg.os.includes('win32')) problems.push('"os" should include win32 (native Windows tool)')
  if (problems.length) addCheck('meta', 'package.json carries the DSH plugin fields', 'fail', problems.join('; '))
  else addCheck('meta', 'package.json carries the DSH plugin fields', 'pass',
    'name=' + pkg.name + ' version=' + pkg.version + ' bundle.patch=' + bundlePatch)
} catch (e) {
  addCheck('meta', 'package.json carries the DSH plugin fields', 'fail', 'cannot read/parse package.json: ' + String(e.message || e))
}

// --- 2. cordis.patch.yml -----------------------------------------------------------
const patchPath = join(root, 'cordis.patch.yml')
try {
  const patchText = readText(patchPath)
  const names = [pkg && pkg.name, 'dsh-screenshot'].filter(Boolean)
  const hits = names.filter((n) => new RegExp('(^|\\s)[\\"\']?' + n.replace(/[.*+?^$\{\}()|[\]\\]/g, '\\$&') + '[\\"\']?\\s*$', 'm').test(patchText))
  const hasInsert = /^\s*-\s*insert\s*:/m.test(patchText)
  if (!hasInsert) addCheck('patch', 'cordis.patch.yml inserts the bundle', 'fail', 'no top-level "- insert:" entry')
  else if (!hits.length) addCheck('patch', 'cordis.patch.yml inserts the bundle', 'fail', 'insert entry does not name ' + names.join(' or '))
  else addCheck('patch', 'cordis.patch.yml inserts the bundle', 'pass', 'insert entry found for ' + hits[0])
} catch (e) {
  checkFromError('patch', 'cordis.patch.yml inserts the bundle', e)
}

// --- syntax checks ------------------------------------------------------------------
function syntaxCheck(id, title, filePath) {
  const st = statSafe(filePath)
  if (!st) return addCheck(id, title, 'pending', 'missing: ' + filePath)
  const text = readText(filePath)
  if (PLACEHOLDER.test(text)) return addCheck(id, title, 'pending', 'placeholder module (' + text.length + ' bytes)')
  const r = spawnSync(process.execPath, ['--check', filePath], { encoding: 'utf8' })
  if (r.status !== 0) {
    const err = String(r.stderr || r.stdout || '').trim().split('\n').slice(0, 6).join(' | ')
    return addCheck(id, title, 'fail', 'node --check failed: ' + err)
  }
  return addCheck(id, title, 'pass', text.length + ' bytes parse cleanly')
}
const hostPath = join(root, 'lib', 'index.js')
const clientPath = join(root, 'lib', 'client.js')
const hostSyntax = syntaxCheck('host-syntax', 'lib/index.js parses', hostPath)
const clientSyntax = syntaxCheck('client-syntax', 'lib/client.js parses', clientPath)

// --- 3. host half: import + export shape -------------------------------------------
async function checkHost() {
  if (hostSyntax.status === 'pending') return addCheck('host-load', 'lib/index.js exposes apply()/inject', 'pending', 'module not written yet')
  const text = readText(hostPath)
  const staticApply = /export\s+(?:async\s+)?function\s+apply\s*\(/.test(text) || /export\s+default\b/.test(text)
  const staticInject = /export\s+const\s+inject\s*=/.test(text) || /export\s+let\s+inject\s*=/.test(text)
  let mod = null
  let importError = null
  try {
    mod = await import(pathToFileURL(hostPath).href + '?smoke=' + Date.now())
  } catch (e) {
    importError = e
  }
  if (!mod) {
    const message = String((importError && importError.message) || importError)
    const resolvableOutsideProfile = /ERR_MODULE_NOT_FOUND|Cannot find (module|package)/.test(message + ' ' + String((importError && importError.code) || ''))
    if (resolvableOutsideProfile && staticApply) {
      return addCheck('host-load', 'lib/index.js exposes apply()/inject', 'warn',
        'host module needs a DSH-internal package that only exists inside a profile; static shape check passed (apply, inject=' + staticInject + ')',
        { importError: message.split('\n')[0] })
    }
    return addCheck('host-load', 'lib/index.js exposes apply()/inject', 'fail', 'import failed: ' + message.split('\n')[0])
  }
  const apply = typeof mod.apply === 'function' ? mod.apply
    : (mod.default && typeof mod.default.apply === 'function' ? mod.default.apply
      : (typeof mod.default === 'function' ? mod.default : null))
  const inject = Array.isArray(mod.inject) ? mod.inject : (mod.default && Array.isArray(mod.default.inject) ? mod.default.inject : null)
  const problems = []
  if (!apply) problems.push('no apply() export')
  if (!inject) problems.push('no inject array export')
  if (problems.length) {
    return addCheck('host-load', 'lib/index.js exposes apply()/inject', 'fail',
      problems.join('; ') + ' (exports: ' + Object.keys(mod).join(', ') + ')')
  }
  return addCheck('host-load', 'lib/index.js exposes apply()/inject', 'pass',
    'exports: ' + Object.keys(mod).join(', ') + '; inject=[' + inject.join(', ') + ']')
}

// --- 4. client half: stub load through window.__ModuleLoader__ ----------------------
function makeElement(tag) {
  const el = {
    tagName: String(tag || 'div').toUpperCase(),
    nodeName: String(tag || 'div').toUpperCase(),
    nodeType: 1,
    style: {},
    dataset: {},
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false } },
    children: [],
    childNodes: [],
    innerHTML: '',
    textContent: '',
    innerText: '',
    title: '',
    className: '',
    value: '',
    width: 0,
    height: 0,
    setAttribute() {},
    getAttribute() { return null },
    removeAttribute() {},
    hasAttribute() { return false },
    appendChild(c) { this.children.push(c); return c },
    append() {},
    prepend() {},
    insertBefore(c) { return c },
    removeChild() {},
    remove() {},
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true },
    querySelector() { return null },
    querySelectorAll() { return [] },
    closest() { return null },
    contains() { return false },
    focus() {},
    blur() {},
    click() {},
    getBoundingClientRect() { return { x: 0, y: 0, width: 120, height: 24, top: 0, left: 0, right: 120, bottom: 24 } },
  }
  return el
}
function makeDocument() {
  const doc = {
    readyState: 'complete',
    documentElement: makeElement('html'),
    head: makeElement('head'),
    body: makeElement('body'),
    createElement: (t) => makeElement(t),
    createElementNS: (ns, t) => makeElement(t),
    createTextNode: (t) => ({ nodeType: 3, textContent: String(t) }),
    createDocumentFragment: () => makeElement('fragment'),
    querySelector: () => null,
    querySelectorAll: () => [],
    getElementById: () => null,
    addEventListener() {},
    removeEventListener() {},
    execCommand() { return true },
    fonts: { add() {}, ready: Promise.resolve() },
  }
  doc.documentElement.lang = 'en'
  return doc
}
function makeReactStub() {
  const createElement = (type, props, ...children) => ({ type, props: props || {}, children, key: props && props.key })
  const stub = {
    createElement,
    cloneElement: (el) => el,
    Fragment: 'Fragment',
    StrictMode: 'StrictMode',
    useState: (v) => [typeof v === 'function' ? v() : v, () => {}],
    useReducer: (r, v) => [v, () => {}],
    useEffect: () => {},
    useLayoutEffect: () => {},
    useInsertionEffect: () => {},
    useRef: (v) => ({ current: v === undefined ? null : v }),
    useMemo: (f) => (typeof f === 'function' ? f() : undefined),
    useCallback: (f) => f,
    useContext: () => ({}),
    useId: () => 'smoke-id',
    useSyncExternalStore: (sub, get) => get(),
    createContext: (v) => ({ Provider: 'Provider', Consumer: 'Consumer', _value: v }),
    forwardRef: (f) => f,
    memo: (f) => f,
    Children: { map: (c, f) => (Array.isArray(c) ? c.map(f) : []), toArray: (c) => (Array.isArray(c) ? c : []) },
  }
  // Any hook/helper this stub does not know still returns something callable, so a test
  // double can never turn "the module uses a newer React API" into a smoke crash.
  return new Proxy(stub, {
    get(target, key) {
      if (key in target) return target[key]
      if (key === 'default') return target
      if (typeof key === 'symbol') return undefined
      return () => undefined
    },
  })
}
function checkClient() {
  if (clientSyntax.status === 'pending') return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'pending', 'module not written yet')
  const text = readText(clientPath)
  let captured = null
  const documentStub = makeDocument()
  const windowStub = {
    __ModuleLoader__: { load(def) { captured = def } },
    document: documentStub,
    navigator: { languages: ['en'], language: 'en', userAgent: 'plugin-smoke' },
    location: { href: 'about:blank', hostname: '127.0.0.1', origin: 'http://127.0.0.1' },
    localStorage: { getItem() { return null }, setItem() {}, removeItem() {} },
    fetch: async () => ({ ok: true, json: async () => ({}), text: async () => '' }),
    addEventListener() {},
    removeEventListener() {},
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
    requestAnimationFrame: (f) => setTimeout(f, 0),
    cancelAnimationFrame: () => {},
    devicePixelRatio: 1,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    console,
    URL,
    Blob: class Blob { constructor(parts) { this.parts = parts } },
    FormData: class FormData {},
  }
  const sandbox = {
    window: windowStub,
    document: documentStub,
    navigator: windowStub.navigator,
    localStorage: windowStub.localStorage,
    location: windowStub.location,
    fetch: windowStub.fetch,
    console,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    requestAnimationFrame: windowStub.requestAnimationFrame,
    cancelAnimationFrame: windowStub.cancelAnimationFrame,
    getComputedStyle: windowStub.getComputedStyle,
    matchMedia: windowStub.matchMedia,
    URL,
    Blob: windowStub.Blob,
    FormData: windowStub.FormData,
    TextEncoder,
    TextDecoder,
    MutationObserver: class MutationObserver { observe() {} disconnect() {} },
    ResizeObserver: class ResizeObserver { observe() {} disconnect() {} },
    Image: class Image {},
    atob: (s) => Buffer.from(String(s), 'base64').toString('binary'),
    btoa: (s) => Buffer.from(String(s), 'binary').toString('base64'),
  }
  sandbox.globalThis = sandbox
  sandbox.self = sandbox
  try {
    vm.createContext(sandbox)
    new vm.Script(text, { filename: clientPath }).runInContext(sandbox)
  } catch (e) {
    return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail',
      'evaluating the bundle threw: ' + String((e && e.message) || e).split('\n')[0])
  }
  if (!captured || typeof captured !== 'object') {
    return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail',
      'window.__ModuleLoader__.load() was never called (not a DSH client bundle)')
  }
  const id = captured.id || ''
  const problems = []
  if (!id) problems.push('registration has no id')
  if (typeof captured.factory !== 'function') problems.push('registration has no factory()')
  if (problems.length) return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail', problems.join('; '))

  const react = makeReactStub()
  const requireStub = (name) => {
    if (name === 'react') return react
    if (name === 'react-dom') return { createPortal: (c) => c, render: () => {} }
    return { __smokeStub: String(name) }
  }
  let api = null
  try {
    api = captured.factory(requireStub)
  } catch (e) {
    const staticApply = /exports\.apply\s*=/.test(text)
    const staticInject = /exports\.inject\s*=/.test(text)
    if (staticApply) {
      return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'warn',
        'factory threw under the DOM stub (' + String((e && e.message) || e).split('\n')[0] + '); static shape check passed (inject=' + staticInject + ')',
        { moduleId: id })
    }
    return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail',
      'factory threw under the DOM stub: ' + String((e && e.message) || e).split('\n')[0])
  }
  if (!api || typeof api !== 'object') {
    return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail', 'factory did not return a module object')
  }
  const hasApply = typeof api.apply === 'function' || typeof api.activate === 'function'
  if (!hasApply) return addCheck('client-load', 'lib/client.js registers and exposes apply()/inject', 'fail',
    'module has no apply() (keys: ' + Object.keys(api).join(', ') + ')')
  const inject = Array.isArray(api.inject) ? api.inject : []
  // The stub load above only proves the bundle parses and loads. Web boot executes apply()
  // against the REAL Cordis context, so tools/client-contract.mjs has the final word:
  // undeclared service reads, descriptor-style slots.inject() and single-slot collisions all
  // throw there (v2.0.0 lost web boot that way while this stub still reported "pass").
  let contract = null
  try {
    contract = runContract({ clientPath: clientPath })
  } catch (e) {
    contract = { ok: false, checks: [], failed: [{ id: 'client-contract-crash', category: 'module-load', error: String((e && e.message) || e) }] }
  }
  const contractChecks = (contract && contract.checks) || []
  const contractFailed = (contract && contract.failed) || []
  if (!contract || !contract.ok) {
    const why = contractFailed.length
      ? contractFailed.map(function (f) { return f.id + ' [' + f.category + '] ' + f.error }).join(' | ')
      : 'contract gate returned no verdict'
    return addCheck('client-load', 'lib/client.js passes the real slots contract (not just stub load)', 'fail',
      'stub load ok (id=' + id + ') but the real slots contract fails, so web boot would abort: ' + why,
      { moduleId: id, contractReport: 'out/ev-contract/client-contract.json' })
  }
  const passedCount = contractChecks.filter(function (c) { return c.status === 'pass' }).length
  const negative = contract.negative
  return addCheck('client-load', 'lib/client.js passes the real slots contract (not just stub load)', 'pass',
    'id=' + id + '; apply=' + (typeof api.apply === 'function') + '; inject=[' + inject.join(', ') + ']' +
    '; real slots contract: ' + passedCount + '/' + contractChecks.length + ' checks pass' +
    (negative ? '; negative control rejected the shipped 2.0.0 bundle (' + (negative.observedCategories || []).join(', ') + ')' : ''),
    { moduleId: id })
}

// --- 5. host/native contract --------------------------------------------------------
// The two halves are separate processes: the flags lib/index.js spawns with and the
// wake-up fields it writes to the pipe must be exactly what Program.Main parses. That is
// the integration contract E6 in the task, and it drifts silently otherwise.
function checkCliSync() {
  const id = 'cli-sync'
  const title = 'lib/index.js arguments match the native CLI parser'
  const csPath = join(root, 'src', 'SnipTool.cs')
  if (!statSafe(hostPath)) return addCheck(id, title, 'pending', 'lib/index.js missing')
  if (!statSafe(csPath)) return addCheck(id, title, 'pending', 'src/SnipTool.cs missing')
  const host = readText(hostPath)
  const cs = readText(csPath)
  const clientPath = join(root, 'lib', 'client.js')
  const client = statSafe(clientPath) ? readText(clientPath) : ''

  // The argument loop is the only place that may declare a flag.
  const loopAt = cs.indexOf('for (int i = 0; i < args.Length; i++)')
  if (loopAt < 0) return addCheck(id, title, 'fail', 'cannot find the argument loop in src/SnipTool.cs')
  const loopEnd = cs.indexOf('\n        }\n', loopAt)
  const loop = cs.slice(loopAt, loopEnd > 0 ? loopEnd : loopAt + 4000)
  const nativeFlags = new Set()
  const valueFlags = new Set()
  const flagRe = /args\[i\]\s*==\s*"(--[a-z-]+)"/g
  let m
  while ((m = flagRe.exec(loop)) !== null) {
    nativeFlags.add(m[1])
    const rest = loop.slice(m.index, m.index + 220)
    if (/i \+ 1 < args\.Length/.test(rest)) valueFlags.add(m[1])
  }
  if (!nativeFlags.size) return addCheck(id, title, 'fail', 'no flags found in the native argument loop')

  // Flags the host half actually passes (spawn argv) — string literals in lib/index.js.
  const hostFlags = new Set()
  const hostRe = /'(--[a-z-]+)'/g
  while ((m = hostRe.exec(host)) !== null) hostFlags.add(m[1])

  const problems = []
  const passed = [...hostFlags].sort()
  for (const flag of passed) {
    if (!nativeFlags.has(flag)) problems.push('host passes ' + flag + ' but Program.Main does not parse it')
  }
  for (const flag of ['--serve', '--parent', '--out', '--client', '--lang']) {
    if (!hostFlags.has(flag)) problems.push('host never passes ' + flag)
    if (!nativeFlags.has(flag)) problems.push('Program.Main does not parse ' + flag)
  }
  for (const flag of ['--parent', '--out', '--lang']) {
    if (!valueFlags.has(flag)) problems.push(flag + ' must take a value (i + 1 < args.Length)')
  }
  // v2.1 contract: hiding DSH is a per-click decision (left click = keep, right click = hide),
  // so the host MUST carry the flag on both paths and the native side MUST parse both.
  for (const flag of ['--hide', '--no-hide']) {
    if (!hostFlags.has(flag)) problems.push('host never passes ' + flag + ' on the cold-start path')
    if (!nativeFlags.has(flag)) problems.push('Program.Main does not parse ' + flag)
  }
  for (const field of ['hide=1', 'hide=0']) {
    if (host.indexOf(field) < 0) problems.push('lib/index.js never sends ' + field + ' on the wake line')
    if (cs.indexOf(field) < 0) problems.push('the native serve loop does not understand ' + field)
  }
  if (!/hide:\s*!!hide/.test(client)) problems.push('lib/client.js does not forward the click side as hide')
  if (/Settings\.Load/.test(cs)) problems.push('src/SnipTool.cs still reads a settings file for the hide flag')
  // The host half is an ES module: "require" would throw at runtime and be swallowed.
  if (/\brequire\s*\(/.test(host)) problems.push('lib/index.js uses require() inside an ES module')
  if (!/client=1/.test(host)) problems.push('host does not tell the native side client=1 (double paste risk)')
  if (!/out=/.test(host)) problems.push('host never sends the result directory on the pipe')

  if (problems.length) return addCheck(id, title, 'fail', problems.join('; '))
  return addCheck(id, title, 'pass',
    'host passes [' + passed.join(' ') + ']; native parses [' + [...nativeFlags].sort().join(' ') + ']; hide travels per click (hide=1/0 + --hide/--no-hide)',
    { hostFlags: passed, nativeFlags: [...nativeFlags].sort(), valueFlags: [...valueFlags].sort() })
}

// --- 6. binary (informational) ------------------------------------------------------
function checkBinary() {
  const exe = join(root, 'bin', 'SnipTool.exe')
  const st = statSafe(exe)
  if (!st) return addCheck('binary', 'bin/SnipTool.exe exists', 'pending', 'native tool has not been built (run build.ps1)')
  return addCheck('binary', 'bin/SnipTool.exe exists', 'pass', Math.round(st.size / 1024) + ' KiB, modified ' + st.mtime.toISOString())
}

await checkHost()
checkClient()
checkCliSync()
checkBinary()

// --- summary ------------------------------------------------------------------------
const count = (s) => checks.filter((c) => c.status === s).length
const status = count('fail') > 0 ? 'fail' : (count('pending') > 0 ? 'pending' : 'pass')
const result = {
  schema: 'dsh-screenshot-plugin-smoke/v1',
  generatedAt: new Date().toISOString(),
  root,
  node: process.version,
  package: pkg ? { name: pkg.name, version: pkg.version, type: pkg.type || null } : null,
  status,
  counts: { pass: count('pass'), warn: count('warn'), pending: count('pending'), fail: count('fail') },
  checks,
}
const summaryLines = [
  'plugin-smoke: ' + status.toUpperCase() + ' (' + result.counts.pass + ' pass, ' + result.counts.warn + ' warn, '
    + result.counts.pending + ' pending, ' + result.counts.fail + ' fail)',
  ...checks.map((c) => '  ' + c.status.padEnd(7) + ' ' + c.id + ' — ' + c.title + (c.detail ? ': ' + c.detail : '')),
]
result.summary = summaryLines.join('\n')
if (!quiet) console.log('\n' + result.summary)
if (jsonPath) {
  mkdirSync(dirname(resolve(jsonPath)), { recursive: true })
  writeFileSync(resolve(jsonPath), JSON.stringify(result, null, 2) + '\n', 'utf8')
}
process.exit(status === 'fail' ? 1 : 0)