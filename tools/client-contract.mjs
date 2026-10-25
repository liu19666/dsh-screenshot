#!/usr/bin/env node
// tools/client-contract.mjs — Cordis slots contract gate for lib/client.js (web half), modeled
// on the real DSH web shell. Which drills are copied from the real renderer verbatim and which
// are this gate's own guardrails is spelled out under "Modeled contract" below.
//
// Why this file exists
// --------------------
// v2.0.0 shipped a lib/client.js that passed a *stub* smoke test and still killed the
// DSH desktop web boot (log: "web boot: 1 entry did not activate" / "dsh-screenshot:
// failed") because it broke three real contract rules of the Cordis-based web shell:
//
//   1. it read ctx.slots without declaring exports.inject = ['slots']
//        -> Error: cannot get property "slots" without inject
//   2. it called ctx.slots.inject(key, descriptorObject). The real signature is
//      inject(key, callback); the callback is installed through ctx.effect() and must
//      RETURN the disposer(s) created by slots.register(options, Component).
//        -> TypeError: callback is not a function
//   3. after fixing (2) it registered into "conversation.input.activity", a SINGLE slot
//      whose only registration already belongs to the voice-input button.
//        -> Error: single slot "conversation.input.activity" already has a registration at priority 0
//
// tools/plugin-smoke.mjs loads the bundle with a stub __ModuleLoader__ / React / DOM. That
// proves the bundle parses and loads, not that the real web shell will accept it. This gate
// adds the missing layer: a small faithful model of the Cordis context a client entry of
// this plugin touches, plus a hard negative control built from the shipped 2.0.0 bundle
// (tools/fixtures/client-470abc0e.js) which MUST be rejected with those three categories.
//
// Modeled contract — TWO drills are copied from the real shell VERBATIM, TWO are guardrails
// this gate adds on purpose. All four are hard failures; provenance only says how much
// authority the message text carries. Every check row reports it as `provenance`:
// real-verbatim | harness-guardrail | derived.
//
// VERBATIM — message text and trigger copied from the installed DSH renderer / boot log
//   ctx.<service>              reading a service not listed in exports.inject throws
//                              cannot get property "<service>" without inject
//                              (reflect.ts:144)
//   SINGLE-slot duplicate      a single slot that already holds a registration at the same
//                              priority throws
//                              single slot "<key>" already has a registration at priority <n>
//                              (installed web bundle, offset 487707)
//
// GUARDRAILS — stricter than the real shell, NOT verbatim; never cite these strings as the
// real Cordis message
//   ctx.effect(cb) / slots.inject(key, cb)
//                              the real effect path rejects a non-callable callback with
//                              TypeError("Invalid effect"); this gate throws
//                              "callback is not a function" instead — that is the string the
//                              v2.0.0 boot log showed, so the failure stays recognizable, but
//                              it is NOT byte-identical to the real throw. What the gate does
//                              model faithfully is the API shape: cb is installed through
//                              ctx.effect(), runs in the same synchronous turn, and its return
//                              value is the disposer.
//   slots.register(opt, C)     the real register() does NOT validate opt.name; this gate
//                              requires opt.name === the injected key (error text "does not
//                              match the injected slot"). That is our own rail: landing in the
//                              wrong slot is exactly how v2.0.0 registered into the single
//                              activity slot. C must be a function and a registration returns
//                              a disposer, per the real API; multi slots accept many.
//
// Usage
//   node tools/client-contract.mjs [--root <repo>] [--client <file>] [--negative-client <file>]
//                                  [--json <file>] [--quiet] [--no-negative]
//   node tools/client-contract.mjs --update-baseline --reason "<why>"
//
// Exit code 0 only when the current bundle passes AND the negative control is rejected
// with all three error categories. A lib/client.js whose sha256 differs from the recorded
// baseline (tools/fixtures/client-baseline.json) is REPORTED as a warning and never failed:
// the bundle is source that legitimate work changes, the contract checks are what must hold.
// The baseline moves only through the explicit "--update-baseline --reason <why>" command
// above, and only for a bundle that passes every contract check — otherwise a broken bundle
// could be blessed into the baseline, which is how v2.0.0 shipped.
//
// JSON schema: dsh-screenshot-client-contract/v1 (consumed by tools/e2e.ps1).

import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import vm from 'node:vm'

const HERE = dirname(fileURLToPath(import.meta.url))
export const REPO_ROOT = resolve(HERE, '..')
export const SCHEMA = 'dsh-screenshot-client-contract/v1'

// sha256 of lib/client.js as shipped in the broken 2.0.0 build (negative control).
export const EXPECTED_OLD_SHA256 = '470abc0e7b6d35fba0eaaac1806a861f73dfe11aa6161472089895d6da84deee'
export const BASELINE_SCHEMA = 'dsh-screenshot-client-baseline/v1'
// Fallback when tools/fixtures/client-baseline.json is missing: the repaired bundle this gate
// was first written against. Recorded drift is a warning, never a failure (see BASELINE below).
export const DEFAULT_BASELINE_SHA256 = '3c58aaa2c38ebcfac52a52a37b6947f5554078cd5744ed8c5c21bcbf44df992e'
// Kept as an alias for older callers; new code reads loadBaseline().
export const EXPECTED_CURRENT_SHA256 = DEFAULT_BASELINE_SHA256

const MSG = {
  inject: 'cannot get property "slots" without inject',
  callback: 'callback is not a function',
  single: 'single slot "conversation.input.activity" already has a registration at priority 0',
}

// Where each drill comes from. 'real-verbatim' = the installed shell throws the same text on the
// same trigger; 'harness-guardrail' = stricter than the real shell and NOT its message text;
// 'derived' = behavior inferred from the real API but not a copied error string.
const PROVENANCE = {
  'sem-inject-guard': 'real-verbatim',        // reflect.ts:144
  'sem-single-guard': 'real-verbatim',        // installed web bundle @487707
  'sem-callback-guard': 'harness-guardrail',  // real: TypeError("Invalid effect")
  'sem-name-guard': 'harness-guardrail',      // real: register() ignores options.name
  'sem-multi-coexist': 'derived',             // real: multi slots accept many registrations
}

// Human-readable contract provenance, embedded in every report so a downstream reader never has
// to guess which error strings are the shell's and which are this gate's.
const CONTRACT_PROVENANCE = {
  verbatim: [
    { id: 'missing-inject', source: 'reflect.ts:144', message: MSG.inject },
    { id: 'single-slot-conflict', source: 'installed web bundle @487707', message: MSG.single },
  ],
  guardrails: [
    { id: 'non-function-callback', realBehavior: 'TypeError("Invalid effect") when ctx.effect() gets a non-callable', gateMessage: MSG.callback },
    { id: 'register-name', realBehavior: 'slots.register() does not validate options.name', gateMessage: 'does not match the injected slot' },
  ],
}

// Services a DSH client entry may request through exports.inject.
const KNOWN_SERVICES = ['slots', 'locale', 'theme', 'webServer', 'http', 'logger', 'settings', 'config', 'store', 'router', 'typert', 'i18n']

// Slots of the conversation input row as they exist before this plugin activates.
// "conversation.input.activity" is a SINGLE slot: the voice-input button owns it.
const PRE_EXISTING_SLOTS = {
  'conversation.input.activity': { type: 'single', regs: [{ id: 'voice-input-activity', priority: 0 }] },
  'conversation.input.right': { type: 'multi', regs: [] },
  'conversation.input.left': { type: 'multi', regs: [] },
  'conversation.input.below': { type: 'multi', regs: [] },
  'sidebar.footer': { type: 'multi', regs: [] },
}

export const EXPECTED_NEGATIVE_CATEGORIES = ['missing-inject', 'non-function-callback', 'single-slot-conflict']

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

export function errText(error) {
  if (!error) return ''
  const text = (error && error.message) ? error.message : String(error)
  return String(text).split('\n')[0].trim()
}

export function classifyError(text) {
  const s = String(text || '')
  if (!s) return null
  if (s.indexOf('without inject') >= 0) return 'missing-inject'
  if (s.indexOf('callback is not a function') >= 0) return 'non-function-callback'
  if (s.indexOf('single slot "') >= 0 && s.indexOf('already has a registration') >= 0) return 'single-slot-conflict'
  return 'other-error'
}

function describeRegs(rows) {
  if (!rows || rows.length === 0) return 'none'
  return rows.map(function (r) { return r.slot + '/' + r.id + '@' + r.priority }).join(', ')
}

// ---------------------------------------------------------------------------
// the modeled slots service
// ---------------------------------------------------------------------------

// createSlots({ compat }) — compat=false models the real inject(key, callback) signature.
// compat=true additionally accepts a descriptor object as the second argument and routes it
// through register(); that is how the gate replays "what happens after the callback fix"
// for the old bundle, which passes { id, order, component } descriptors.
export function createSlots(options) {
  const opts = options || {}
  const compat = !!opts.compat
  const model = new Map()
  for (const key of Object.keys(PRE_EXISTING_SLOTS)) {
    const def = PRE_EXISTING_SLOTS[key]
    const regs = def.regs.map(function (r) {
      return { id: r.id, name: key, priority: r.priority, component: function () { return null }, preExisting: true }
    })
    model.set(key, { type: def.type, regs: regs })
  }
  const effects = []
  let currentKey = null

  function slotFor(key) {
    const slot = model.get(key)
    if (!slot) throw new Error('slot "' + key + '" does not exist in this context')
    return slot
  }

  function register(optionsArg, Component) {
    const desc = optionsArg || {}
    if (typeof Component !== 'function') throw new TypeError('slots.register: component is not a function')
    const key = desc.name || currentKey
    if (!key) throw new Error('slots.register: options.name is required')
    if (currentKey && desc.name && desc.name !== currentKey) {
      throw new Error('slots.register: options.name "' + desc.name + '" does not match the injected slot "' + currentKey + '"')
    }
    const slot = slotFor(key)
    const priority = typeof desc.order === 'number' ? desc.order : 0
    if (slot.type === 'single' && slot.regs.length > 0) {
      throw new Error('single slot "' + key + '" already has a registration at priority ' + slot.regs[0].priority)
    }
    const reg = { id: desc.id || ('anonymous-' + (slot.regs.length + 1)), name: key, priority: priority, component: Component, preExisting: false }
    slot.regs.push(reg)
    return function dispose() {
      const at = slot.regs.indexOf(reg)
      if (at >= 0) slot.regs.splice(at, 1)
    }
  }

  function effect(callback) {
    if (typeof callback !== 'function') throw new TypeError('callback is not a function')
    const produced = callback()
    const disposers = Array.isArray(produced) ? produced : [produced]
    const dispose = function () {
      for (const d of disposers) if (typeof d === 'function') d()
    }
    effects.push(dispose)
    return dispose
  }

  function withKey(key, fn) {
    const previous = currentKey
    currentKey = key
    try { return fn() } finally { currentKey = previous }
  }

  function inject(key, callbackOrDescriptor) {
    if (typeof callbackOrDescriptor === 'function') {
      slotFor(key)
      return withKey(key, function () { return effect(callbackOrDescriptor) })
    }
    if (compat && callbackOrDescriptor && typeof callbackOrDescriptor === 'object') {
      const descriptor = callbackOrDescriptor
      return withKey(key, function () {
        return register({ name: key, id: descriptor.id, order: descriptor.order }, descriptor.component)
      })
    }
    throw new TypeError('callback is not a function')
  }

  function snapshot() {
    const rows = []
    for (const entry of model) {
      const key = entry[0]
      const slot = entry[1]
      for (const reg of slot.regs) {
        rows.push({ slot: key, name: reg.name, id: reg.id, priority: reg.priority, preExisting: !!reg.preExisting, component: typeof reg.component })
      }
    }
    return rows
  }

  function disposeAll() {
    for (const d of effects.splice(0)) d()
  }

  return { inject: inject, register: register, effect: effect, snapshot: snapshot, disposeAll: disposeAll, compat: compat }
}

// ---------------------------------------------------------------------------
// the modeled application context
// ---------------------------------------------------------------------------

// createCtx({ injectList, slots, strict }) — strict=true rejects every service read that is
// not declared in exports.inject, exactly like the Cordis service proxy.
export function createCtx(options) {
  const opts = options || {}
  const injectList = opts.injectList || []
  const declared = new Set(injectList)
  const slots = opts.slots
  const strict = opts.strict !== false
  const logger = { info: function () {}, warn: function () {}, error: function () {}, debug: function () {} }
  const values = {
    slots: slots,
    locale: { get: function () { return 'en' }, language: 'en' },
    theme: { get: function () { return 'light' } },
    webServer: {}, http: {}, logger: logger, settings: {}, config: {}, store: {}, router: {}, typert: {}, i18n: {},
  }
  const target = {
    effect: function (callback) { return slots.effect(callback) },
    on: function () {}, off: function () {}, emit: function () {}, get: function () {}, set: function () {},
    plugin: function () {}, provide: function () {}, inject: function () {},
  }
  Object.assign(target, values)
  if (!strict) return target
  return new Proxy(target, {
    get: function (t, prop) {
      if (typeof prop !== 'string') return t[prop]
      if (prop === 'then' || prop === 'toJSON') return undefined
      if (KNOWN_SERVICES.indexOf(prop) >= 0 && !declared.has(prop)) {
        throw new Error('cannot get property "' + prop + '" without inject')
      }
      return t[prop]
    },
  })
}

// ---------------------------------------------------------------------------
// loading a browser bundle through window.__ModuleLoader__
// ---------------------------------------------------------------------------

function makeElement(tag) {
  const el = {
    tagName: String(tag || 'div').toUpperCase(),
    nodeName: String(tag || 'div').toUpperCase(),
    nodeType: 1,
    style: {},
    dataset: {},
    classList: { add: function () {}, remove: function () {}, toggle: function () {}, contains: function () { return false } },
    children: [],
    childNodes: [],
    innerHTML: '', textContent: '', innerText: '', title: '', className: '', value: '', id: '',
    width: 0, height: 0,
    setAttribute: function () {}, getAttribute: function () { return null }, removeAttribute: function () {},
    hasAttribute: function () { return false },
    appendChild: function (c) { this.children.push(c); return c },
    append: function () {}, prepend: function () {}, insertBefore: function (c) { return c },
    removeChild: function () {}, remove: function () {},
    addEventListener: function () {}, removeEventListener: function () {},
    dispatchEvent: function () { return true },
    focus: function () {}, blur: function () {}, click: function () {},
    getBoundingClientRect: function () { return { top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0, x: 0, y: 0 } },
    querySelector: function () { return null },
    querySelectorAll: function () { return [] },
    contains: function () { return false },
    closest: function () { return null },
  }
  return el
}

function makeDocument() {
  const doc = {
    readyState: 'complete',
    documentElement: makeElement('html'),
    head: makeElement('head'),
    body: makeElement('body'),
    createElement: function (t) { return makeElement(t) },
    createElementNS: function (ns, t) { return makeElement(t) },
    createTextNode: function (t) { return { nodeType: 3, textContent: String(t) } },
    createDocumentFragment: function () { return makeElement('fragment') },
    querySelector: function () { return null },
    querySelectorAll: function () { return [] },
    getElementById: function () { return null },
    addEventListener: function () {}, removeEventListener: function () {},
    execCommand: function () { return true },
    fonts: { add: function () {}, ready: Promise.resolve() },
  }
  doc.documentElement.lang = 'en'
  return doc
}

function makeReactStub() {
  const stub = {
    createElement: function (type, props) { return { type: type, props: props || {}, children: Array.prototype.slice.call(arguments, 2) } },
    cloneElement: function (el) { return el },
    Fragment: 'Fragment',
    StrictMode: 'StrictMode',
    useState: function (v) { return [typeof v === 'function' ? v() : v, function () {}] },
    useReducer: function (r, v) { return [v, function () {}] },
    useEffect: function () {}, useLayoutEffect: function () {}, useInsertionEffect: function () {},
    useRef: function (v) { return { current: v === undefined ? null : v } },
    useMemo: function (f) { return typeof f === 'function' ? f() : undefined },
    useCallback: function (f) { return f },
    useContext: function () { return {} },
    useId: function () { return 'contract-id' },
    useSyncExternalStore: function (sub, get) { return get() },
    createContext: function (v) { return { Provider: 'Provider', Consumer: 'Consumer', _value: v } },
    forwardRef: function (f) { return f },
    memo: function (f) { return f },
    Children: { map: function (c, f) { return Array.isArray(c) ? c.map(f) : [] }, toArray: function (c) { return Array.isArray(c) ? c : [] } },
  }
  stub.default = stub
  return new Proxy(stub, {
    get: function (target, key) {
      if (key in target) return target[key]
      if (typeof key === 'symbol') return undefined
      return function () { return undefined }
    },
  })
}

// loadBundle(path) -> { ok, api, id, error, text }
export function loadBundle(clientPath) {
  const text = readFileSync(clientPath, 'utf8')
  let captured = null
  const documentStub = makeDocument()
  const windowStub = {
    __ModuleLoader__: { load: function (def) { captured = def } },
    document: documentStub,
    navigator: { languages: ['en'], language: 'en', userAgent: 'client-contract' },
    location: { href: 'about:blank', hostname: '127.0.0.1', origin: 'http://127.0.0.1' },
    localStorage: { getItem: function () { return null }, setItem: function () {}, removeItem: function () {} },
    fetch: async function () { return { ok: true, json: async function () { return {} }, text: async function () { return '' } } },
    addEventListener: function () {}, removeEventListener: function () {},
    getComputedStyle: function () { return { getPropertyValue: function () { return '' } } },
    matchMedia: function () { return { matches: false, addEventListener: function () {}, addListener: function () {} } },
    requestAnimationFrame: function (f) { return setTimeout(f, 0) },
    cancelAnimationFrame: function () {},
    devicePixelRatio: 1,
    setTimeout: setTimeout, clearTimeout: clearTimeout, setInterval: setInterval, clearInterval: clearInterval,
    console: console, URL: URL,
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
    console: console,
    setTimeout: setTimeout, clearTimeout: clearTimeout, setInterval: setInterval, clearInterval: clearInterval,
    requestAnimationFrame: windowStub.requestAnimationFrame, cancelAnimationFrame: windowStub.cancelAnimationFrame,
    getComputedStyle: windowStub.getComputedStyle, matchMedia: windowStub.matchMedia,
    URL: URL, Blob: windowStub.Blob, FormData: windowStub.FormData,
    TextEncoder: TextEncoder, TextDecoder: TextDecoder,
    MutationObserver: class MutationObserver { observe() {} disconnect() {} takeRecords() { return [] } },
    ResizeObserver: class ResizeObserver { observe() {} disconnect() {} },
    Image: class Image {},
    atob: function (s) { return Buffer.from(String(s), 'base64').toString('binary') },
    btoa: function (s) { return Buffer.from(String(s), 'binary').toString('base64') },
  }
  sandbox.globalThis = sandbox
  sandbox.self = sandbox
  try {
    vm.createContext(sandbox)
    new vm.Script(text, { filename: clientPath }).runInContext(sandbox)
  } catch (e) {
    return { ok: false, error: 'evaluating the bundle threw: ' + errText(e), text: text, id: '' }
  }
  if (!captured || typeof captured !== 'object') {
    return { ok: false, error: 'window.__ModuleLoader__.load() was never called (not a DSH client bundle)', text: text, id: '' }
  }
  if (typeof captured.factory !== 'function') {
    return { ok: false, error: 'registration has no factory()', text: text, id: String(captured.id || '') }
  }
  const react = makeReactStub()
  const requireStub = function (name) {
    if (name === 'react') return react
    if (name === 'react-dom') return { createPortal: function (c) { return c }, render: function () {} }
    return { __contractStub: String(name) }
  }
  try {
    const api = captured.factory(requireStub)
    if (!api || (typeof api !== 'object' && typeof api !== 'function')) return { ok: false, error: 'factory() did not return a module object', text: text, id: String(captured.id || '') }
    return { ok: true, api: api, id: String(captured.id || ''), text: text }
  } catch (e) {
    return { ok: false, error: 'factory() threw: ' + errText(e), text: text, id: String(captured.id || '') }
  }
}

// ---------------------------------------------------------------------------
// scenarios
// ---------------------------------------------------------------------------

// applyScenario(api, { strict, compat }) activates the module on a fresh context and reports
// what it registered, what it threw, and whether disposing leaves no residue.
export function applyScenario(api, options) {
  const opts = options || {}
  const injectList = Array.isArray(api.inject) ? api.inject.filter(function (x) { return typeof x === 'string' }) : []
  const slots = createSlots({ compat: !!opts.compat })
  const baseline = slots.snapshot()
  const ctx = createCtx({ injectList: injectList, slots: slots, strict: opts.strict !== false })
  const entry = typeof api.apply === 'function' ? api.apply : (typeof api.activate === 'function' ? api.activate : null)
  let error = null
  if (!entry) {
    error = new Error('module has no apply()/activate() export')
  } else {
    try { entry.call(api, ctx) } catch (e) { error = e }
  }
  const added = slots.snapshot().filter(function (r) { return !r.preExisting })
  let remaining = 0
  try {
    slots.disposeAll()
    remaining = slots.snapshot().filter(function (r) { return !r.preExisting }).length
  } catch (e) {
    remaining = -1
  }
  const text = errText(error)
  return {
    ok: error === null,
    error: error,
    errorText: text,
    category: classifyError(text),
    injectList: injectList,
    baseline: baseline,
    added: added,
    remaining: remaining,
  }
}

// ---------------------------------------------------------------------------
// semantics self-tests: prove the model rejects what the real shell rejects
// ---------------------------------------------------------------------------

function makeCheck(id, title, ok, detail, category) {
  const row = { id: id, title: title, status: ok ? 'pass' : 'fail', detail: detail || '', provenance: PROVENANCE[id] || 'derived' }
  if (!ok) row.category = category || 'harness-broken'
  return row
}

export function runSemantics() {
  const rows = []
  const ctxModule = { apply: function (ctx) { return ctx.slots } }
  const s1 = applyScenario(ctxModule, { strict: true })
  rows.push(makeCheck('sem-inject-guard', 'reading an undeclared service throws cannot get property "slots" without inject',
    !s1.ok && s1.errorText.indexOf(MSG.inject) >= 0,
    s1.ok ? 'no throw (the model is too lenient)' : s1.errorText, 'harness-broken'))

  const callbackModule = { inject: ['slots'], apply: function (ctx) { ctx.slots.inject('conversation.input.right', { id: 'x', order: 1, component: function () { return null } }) } }
  const s2 = applyScenario(callbackModule, { strict: true })
  rows.push(makeCheck('sem-callback-guard', 'slots.inject(key, nonFunction) throws callback is not a function',
    !s2.ok && s2.errorText.indexOf(MSG.callback) >= 0,
    s2.ok ? 'no throw (descriptor objects would be accepted)' : s2.errorText, 'harness-broken'))

  const singleModule = {
    inject: ['slots'],
    apply: function (ctx) {
      ctx.slots.inject('conversation.input.activity', function () {
        return ctx.slots.register({ name: 'conversation.input.activity', id: 'dupe', order: 0 }, function Dupe() { return null })
      })
    },
  }
  const s3 = applyScenario(singleModule, { strict: true })
  rows.push(makeCheck('sem-single-guard', 'a second registration into the single activity slot throws the exact Cordis duplicate error',
    !s3.ok && s3.errorText.indexOf(MSG.single) >= 0,
    s3.ok ? 'no throw (single slots would accept duplicates)' : s3.errorText, 'harness-broken'))

  const multiModule = {
    inject: ['slots'],
    apply: function (ctx) {
      ctx.slots.inject('conversation.input.right', function () {
        return ctx.slots.register({ name: 'conversation.input.right', id: 'a', order: 100 }, function A() { return null })
      })
      ctx.slots.inject('conversation.input.right', function () {
        return ctx.slots.register({ name: 'conversation.input.right', id: 'b', order: 200 }, function B() { return null })
      })
    },
  }
  const s4 = applyScenario(multiModule, { strict: true })
  rows.push(makeCheck('sem-multi-coexist', 'two registrations coexist in a multi slot and both dispose cleanly',
    s4.ok && s4.added.length === 2 && s4.remaining === 0,
    s4.ok ? ('registrations=' + s4.added.length + ' remaining=' + s4.remaining) : s4.errorText, 'harness-broken'))

  const mismatchModule = {
    inject: ['slots'],
    apply: function (ctx) {
      ctx.slots.inject('conversation.input.right', function () {
        return ctx.slots.register({ name: 'conversation.input.left', id: 'mismatch' }, function M() { return null })
      })
    },
  }
  const s5 = applyScenario(mismatchModule, { strict: true })
  rows.push(makeCheck('sem-name-guard', 'slots.register rejects an options.name that differs from the injected key',
    !s5.ok && s5.errorText.indexOf('does not match the injected slot') >= 0,
    s5.ok ? 'no throw (a registration could land in the wrong slot)' : s5.errorText, 'harness-broken'))
  return rows
}


// ---------------------------------------------------------------------------
// module analysis (shared by the positive run and the negative control)
// ---------------------------------------------------------------------------

// analyzeApi(api) -> { ok, checks, failed, registrations }
export function analyzeApi(api) {
  const checks = []
  const failed = []
  function add(id, title, ok, detail, category) {
    const guardrailed = (id === 'register-name-contract')
    const row = { id: id, title: title, status: ok ? 'pass' : 'fail', detail: detail || '', provenance: guardrailed ? 'harness-guardrail' : 'derived' }
    if (!ok) row.category = category || 'other-error'
    checks.push(row)
    if (!ok) failed.push({ id: id, category: row.category, error: row.detail || title })
    return ok
  }

  const inject = Array.isArray(api.inject) ? api.inject.filter(function (x) { return typeof x === 'string' }) : []
  const hasApply = typeof api.apply === 'function' || typeof api.activate === 'function'
  const strictRun = applyScenario(api, { strict: true })
  const lenientRun = applyScenario(api, { strict: false, compat: false })
  const compatRun = applyScenario(api, { strict: false, compat: true })

  add('inject-declared', 'exports.inject declares every service the entry reads (needs "slots")',
    inject.indexOf('slots') >= 0,
    inject.length ? ('inject=[' + inject.join(', ') + ']') : 'exports.inject is missing entirely: the host throws on the first ctx.slots read',
    'missing-inject')

  add('apply-exported', 'module exposes a callable apply(ctx)/activate(ctx)', hasApply,
    'apply=' + (typeof api.apply === 'function' ? 'function' : 'absent') + '; activate=' + (typeof api.activate === 'function' ? 'function' : 'absent'),
    'missing-apply')

  add('apply-clean', 'apply(ctx) activates against a faithful slots context without throwing',
    strictRun.ok,
    strictRun.ok ? ('registrations: ' + describeRegs(strictRun.added)) : strictRun.errorText,
    strictRun.ok ? null : (strictRun.category || 'other-error'))

  add('callback-signature', 'slots.inject(key, callback) is called with a real callback (effect semantics)',
    lenientRun.ok,
    lenientRun.ok ? ('callback accepted; registrations: ' + describeRegs(lenientRun.added)) : lenientRun.errorText,
    lenientRun.ok ? null : (lenientRun.category || 'other-error'))

  add('slot-choice', 'the entry never registers into a single slot that is already occupied',
    compatRun.ok,
    compatRun.ok ? ('registrations: ' + describeRegs(compatRun.added)) : compatRun.errorText,
    compatRun.ok ? null : (compatRun.category || 'other-error'))

  if (strictRun.ok) {
    add('registrations-enumerable', 'at least one slot registration is observable after apply()',
      strictRun.added.length > 0,
      'count=' + strictRun.added.length + ' [' + describeRegs(strictRun.added) + ']',
      'other-error')

    const nameOk = strictRun.added.length > 0 && strictRun.added.every(function (r) { return r.name === r.slot })
    add('register-name-contract', 'every registration repeats the injected slot key in options.name', nameOk,
      strictRun.added.length ? describeRegs(strictRun.added) : 'no registrations to inspect',
      'other-error')

    add('dispose-clean', 'disposing the injected effect removes every registration',
      strictRun.remaining === 0,
      'remaining after dispose=' + strictRun.remaining,
      'other-error')
  }

  const registrations = strictRun.ok ? strictRun.added : (compatRun.ok ? compatRun.added : lenientRun.added)
  return { ok: failed.length === 0, checks: checks, failed: failed, registrations: registrations }
}

// ---------------------------------------------------------------------------
// sha baseline: a record for humans, never a pass/fail criterion
// ---------------------------------------------------------------------------
// lib/client.js is source that legitimate work changes (t28 removed the DOM-mover hack and the
// bytes differed while the contract still held). Pinning sha256 as a hard failure therefore
// locks plugin authors out: the gate made a legal edit look like a regression. So the baseline
// only answers "which bundle was reviewed?" and moves only when a human says so, with a reason.
export function baselineFilePath(root) {
  return join(resolve(root || REPO_ROOT), 'tools', 'fixtures', 'client-baseline.json')
}

// loadBaseline(root) -> { path, sha256, updatedAt, reason, source }
export function loadBaseline(root) {
  const path = baselineFilePath(root)
  const info = { path: path, sha256: DEFAULT_BASELINE_SHA256, updatedAt: null, reason: null, source: 'default' }
  if (!existsSync(path)) return info
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8'))
    if (parsed && typeof parsed.sha256 === 'string' && /^[0-9a-f]{64}$/.test(parsed.sha256)) {
      info.sha256 = parsed.sha256
      info.updatedAt = typeof parsed.updatedAt === 'string' ? parsed.updatedAt : null
      info.reason = typeof parsed.reason === 'string' ? parsed.reason : null
      info.source = 'file'
    } else {
      info.error = 'client-baseline.json has no usable sha256; falling back to the built-in default'
    }
  } catch (e) {
    info.error = 'client-baseline.json is unreadable (' + errText(e) + '); falling back to the built-in default'
  }
  return info
}

// updateBaseline({ root, sha256, reason }) -> { path, record }
// Refuses an empty reason on purpose: the reason is the reviewable half of the record.
export function updateBaseline(options) {
  const opts = options || {}
  const path = baselineFilePath(opts.root)
  const sha = String(opts.sha256 || '')
  const reason = typeof opts.reason === 'string' ? opts.reason.trim() : ''
  if (!/^[0-9a-f]{64}$/.test(sha)) throw new Error('updateBaseline: invalid sha256 "' + sha + '"')
  if (!reason) throw new Error('refusing to update the baseline without --reason "<why>": the reason is what makes the record reviewable')
  const record = {
    schema: BASELINE_SCHEMA,
    sha256: sha,
    updatedAt: new Date().toISOString(),
    reason: reason,
    client: 'lib/client.js',
  }
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(record, null, 2) + '\n', 'utf8')
  return { path: path, record: record }
}

// ---------------------------------------------------------------------------
// public entry points
// ---------------------------------------------------------------------------

// runContract({ clientPath, root }) -> report object (schema dsh-screenshot-client-contract/v1)
export function runContract(options) {
  const opts = options || {}
  const root = opts.root ? resolve(opts.root) : REPO_ROOT
  const clientPath = resolve(opts.clientPath || join(root, 'lib', 'client.js'))
  const baseline = opts.baseline || loadBaseline(root)
  const report = {
    schema: SCHEMA,
    generatedAt: new Date().toISOString(),
    ok: false,
    detail: '',
    client: {
      path: clientPath,
      sha256: null,
      expectedSha256: baseline.sha256,
      shaMatchesExpected: null,
      moduleId: '',
      inject: [],
      applyType: 'absent',
    },
    baseline: {
      path: baseline.path,
      sha256: baseline.sha256,
      updatedAt: baseline.updatedAt,
      reason: baseline.reason,
      source: baseline.source,
      error: baseline.error || null,
    },
    // Drift is a record, not a verdict. It never feeds report.ok.
    drift: {
      matches: null,
      currentSha256: null,
      baselineSha256: baseline.sha256,
      baselineUpdatedAt: baseline.updatedAt,
      baselineReason: baseline.reason,
      baselineSource: baseline.source,
    },
    contract: { verbatim: CONTRACT_PROVENANCE.verbatim, guardrails: CONTRACT_PROVENANCE.guardrails },
    checks: [],
    failed: [],
    registrations: [],
  }

  const semantics = runSemantics()
  for (const row of semantics) {
    report.checks.push(row)
    if (row.status !== 'pass') report.failed.push({ id: row.id, category: 'harness-broken', error: row.detail })
  }
  const semanticsOk = semantics.every(function (row) { return row.status === 'pass' })

  if (!existsSync(clientPath)) {
    const detail = 'missing file: ' + clientPath
    report.checks.push({ id: 'client-present', title: 'lib/client.js exists', status: 'fail', detail: detail, category: 'module-load', provenance: 'derived' })
    report.failed.push({ id: 'client-present', category: 'module-load', error: detail })
    report.detail = 'client bundle missing: ' + clientPath
    return report
  }
  report.checks.push({ id: 'client-present', title: 'lib/client.js exists', status: 'pass', detail: clientPath, provenance: 'derived' })

  report.client.sha256 = sha256File(clientPath)
  report.client.shaMatchesExpected = report.client.sha256 === baseline.sha256
  report.drift.currentSha256 = report.client.sha256
  report.drift.matches = report.client.shaMatchesExpected

  const loaded = loadBundle(clientPath)
  if (!loaded.ok) {
    report.checks.push({ id: 'bundle-load', title: 'bundle evaluates and its factory returns a module', status: 'fail', detail: loaded.error, category: 'module-load', provenance: 'derived' })
    report.failed.push({ id: 'bundle-load', category: 'module-load', error: loaded.error })
    report.client.moduleId = loaded.id || ''
    report.detail = loaded.error
    return report
  }
  report.checks.push({ id: 'bundle-load', title: 'bundle evaluates and its factory returns a module', status: 'pass', detail: 'id=' + loaded.id, provenance: 'derived' })
  report.client.moduleId = loaded.id || ''

  const analysis = analyzeApi(loaded.api)
  for (const row of analysis.checks) report.checks.push(row)
  for (const row of analysis.failed) report.failed.push(row)
  report.registrations = analysis.registrations
  report.client.inject = Array.isArray(loaded.api.inject) ? loaded.api.inject.filter(function (x) { return typeof x === 'string' }) : []
  report.client.applyType = typeof loaded.api.apply === 'function' ? 'apply' : (typeof loaded.api.activate === 'function' ? 'activate' : 'absent')

  report.ok = semanticsOk && analysis.ok
  report.detail = report.ok
    ? ('bundle activates; ' + report.checks.length + ' checks passed; sha256 ' + report.client.sha256 +
       (report.client.shaMatchesExpected ? '' : ' (differs from the recorded baseline ' + baseline.sha256 + ' — warning only)'))
    : (report.failed.length + ' check(s) failed: ' + report.failed.map(function (f) { return f.id + ' [' + f.category + ']' }).join(', '))
  return report
}

// runNegative({ negativeClient }) -> proof that the shipped 2.0.0 bundle is REJECTED.
export function runNegative(options) {
  const opts = options || {}
  const fixture = resolve(opts.negativeClient || join(REPO_ROOT, 'tools', 'fixtures', 'client-470abc0e.js'))
  const report = {
    schema: SCHEMA,
    path: fixture,
    sha256: null,
    expectedSha256: EXPECTED_OLD_SHA256,
    expectedCategories: EXPECTED_NEGATIVE_CATEGORIES.slice(),
    observedCategories: [],
    evidence: [],
    ok: false,
    detail: '',
    checks: [],
    failed: [],
  }
  if (!existsSync(fixture)) {
    report.detail = 'old-client fixture is missing: ' + fixture
    return report
  }
  report.sha256 = sha256File(fixture)
  if (report.sha256 !== EXPECTED_OLD_SHA256) {
    report.detail = 'fixture sha256 ' + report.sha256 + ' is not the bundle shipped in 2.0.0 (' + EXPECTED_OLD_SHA256 + ')'
    return report
  }
  const loaded = loadBundle(fixture)
  if (!loaded.ok) {
    report.detail = 'fixture did not load: ' + loaded.error
    return report
  }
  const analysis = analyzeApi(loaded.api)
  report.checks = analysis.checks
  report.failed = analysis.failed
  const observed = []
  for (const row of analysis.failed) if (row.category && observed.indexOf(row.category) < 0) observed.push(row.category)
  report.observedCategories = observed
  const evidence = []
  for (const row of analysis.failed) {
    if (report.expectedCategories.indexOf(row.category) < 0) continue
    if (evidence.some(function (e) { return e.category === row.category })) continue
    evidence.push({ category: row.category, check: row.id, error: row.error })
  }
  report.evidence = evidence
  const missing = report.expectedCategories.filter(function (c) { return observed.indexOf(c) < 0 })
  report.ok = !analysis.ok && missing.length === 0
  if (report.ok) {
    report.detail = 'the shipped 2.0.0 bundle is rejected with all expected categories (' + observed.join(', ') + ')'
  } else if (analysis.ok) {
    report.detail = 'the shipped 2.0.0 bundle PASSED the gate: the model is not faithful'
  } else {
    report.detail = 'expected failure categories missing: ' + missing.join(', ') + ' (observed: ' + (observed.join(', ') || 'none') + ')'
  }
  return report
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = { quiet: false, negative: true, json: null, root: null, client: null, negativeClient: null, help: false, updateBaseline: false, reason: null }
  for (let i = 0; i < argv.length; i++) {
    const raw = argv[i]
    let key = raw
    let value = null
    const eq = raw.indexOf('=')
    if (raw.slice(0, 2) === '--' && eq > 0) {
      key = raw.slice(0, eq)
      value = raw.slice(eq + 1)
    }
    const take = function () {
      if (value !== null) return value
      i++
      return argv[i]
    }
    if (key === '--root') out.root = take()
    else if (key === '--client') out.client = take()
    else if (key === '--negative-client') out.negativeClient = take()
    else if (key === '--json') out.json = take()
    else if (key === '--quiet') out.quiet = true
    else if (key === '--no-negative') out.negative = false
    else if (key === '--update-baseline') out.updateBaseline = true
    else if (key === '--reason') out.reason = take()
    else if (key === '--help' || key === '-h') out.help = true
    else throw new Error('unknown argument: ' + raw)
  }
  return out
}

function printUsage() {
  console.log('usage: node tools/client-contract.mjs [--root <repo>] [--client <file>] [--negative-client <file>]')
  console.log('                                   [--json <file>] [--quiet] [--no-negative]')
  console.log('       node tools/client-contract.mjs --update-baseline --reason "<why this bundle is reviewed>"')
  console.log('')
  console.log('  The contract checks decide pass/fail. A lib/client.js whose sha256 differs from the')
  console.log('  recorded baseline only produces a warning; accept new bytes with --update-baseline,')
  console.log('  which refuses to record a bundle that fails any contract check.')
}

function printReport(report, opts) {
  const quiet = !!opts.quiet
  console.log('client contract gate  (' + SCHEMA + ')')
  console.log('  client : ' + report.client.path)
  console.log('  sha256 : ' + (report.client.sha256 || 'n/a') + (report.client.shaMatchesExpected === true ? '  (matches the recorded baseline)' : ''))
  if (report.client.inject && report.client.inject.length) console.log('  inject : [' + report.client.inject.join(', ') + ']')
  console.log('  source : 2 checks are copied verbatim from the real shell (missing-inject @reflect.ts:144, single-slot-conflict @bundle+487707);')
  console.log('           2 are this gate\'s own guardrails, not the real message text (callback-not-a-function vs TypeError("Invalid effect"), register name rail);')
  console.log('           every check row carries provenance; all of them are hard failures.')
  if (report.drift && report.drift.matches === false) {
    console.log('  WARN   : sha drift - the bundle bytes differ from the recorded baseline')
    console.log('           current  : ' + report.drift.currentSha256)
    console.log('           baseline : ' + report.drift.baselineSha256 + (report.drift.baselineUpdatedAt ? '  (' + report.drift.baselineUpdatedAt + ')' : ''))
    console.log('           reason   : ' + (report.drift.baselineReason || '(none recorded)') + '   [source: ' + (report.drift.baselineSource || 'default') + ']')
    console.log('           file     : ' + (report.baseline && report.baseline.path))
    console.log('           accept   : node tools/client-contract.mjs --update-baseline --reason "<why this bundle is reviewed>"')
    console.log('           warning only - the contract checks below decide pass/fail')
  }
  if (report.baseline && report.baseline.error) console.log('  WARN   : ' + report.baseline.error)
  for (const row of report.checks) {
    if (quiet && row.status === 'pass') continue
    console.log('  [' + (row.status === 'pass' ? 'PASS' : 'FAIL') + '] ' + row.id + '  ' + row.title)
    if (row.detail) console.log('         ' + row.detail + (row.status === 'pass' ? '' : '  (category: ' + row.category + ')'))
  }
  console.log('  result : ' + (report.ok ? 'PASS' : 'FAIL') + ' - ' + report.detail)
  const neg = report.negative
  if (!neg) return
  console.log('negative control  (the shipped 2.0.0 bundle must be rejected)')
  console.log('  client : ' + neg.path)
  console.log('  sha256 : ' + (neg.sha256 || 'n/a'))
  console.log('  expected: ' + neg.expectedCategories.join(', '))
  console.log('  observed: ' + (neg.observedCategories.join(', ') || 'none'))
  for (const row of neg.evidence) console.log('    - ' + row.category + ': ' + row.error)
  console.log('  result : ' + (neg.ok ? 'PASS' : 'FAIL') + ' - ' + neg.detail)
}

function main() {
  let opts = null
  try {
    opts = parseArgs(process.argv.slice(2))
  } catch (e) {
    console.error(String(errText(e)))
    printUsage()
    process.exit(2)
  }
  if (opts.help) {
    printUsage()
    process.exit(0)
  }
  const root = opts.root ? resolve(opts.root) : REPO_ROOT
  const clientPath = opts.client ? resolve(opts.client) : join(root, 'lib', 'client.js')
  if (opts.updateBaseline) {
    const checked = runContract({ clientPath: clientPath, root: root })
    printReport(checked, { quiet: false })
    if (!checked.ok) {
      console.error('refusing to update the client baseline: this bundle does not pass the contract checks')
      process.exit(1)
    }
    let updated = null
    try {
      updated = updateBaseline({ root: root, sha256: checked.client.sha256, reason: opts.reason })
    } catch (e) {
      console.error(errText(e))
      printUsage()
      process.exit(2)
    }
    console.log('baseline written: ' + updated.path)
    console.log('  sha256 : ' + updated.record.sha256)
    console.log('  reason : ' + updated.record.reason)
    console.log('  at     : ' + updated.record.updatedAt)
    process.exit(0)
  }
  const contract = runContract({ clientPath: clientPath, root: root })
  const negative = opts.negative
    ? runNegative({ negativeClient: opts.negativeClient ? resolve(opts.negativeClient) : join(root, 'tools', 'fixtures', 'client-470abc0e.js') })
    : null
  const output = Object.assign({}, contract, {
    ok: contract.ok && (!negative || negative.ok),
    negative: negative,
  })
  if (!contract.ok) output.detail = contract.detail
  else if (negative && !negative.ok) output.detail = 'positive run passed, but the negative control was not rejected: ' + negative.detail
  printReport(output, opts)
  if (opts.json) {
    const jsonPath = resolve(opts.json)
    mkdirSync(dirname(jsonPath), { recursive: true })
    writeFileSync(jsonPath, JSON.stringify(output, null, 2) + '\n', 'utf8')
    console.log('json: ' + jsonPath)
  }
  process.exit(output.ok ? 0 : 1)
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main()
}
