window.__ModuleLoader__.load({ id: "dsh-screenshot", factory: (require) => {
  var module = { exports: {} }; var exports = module.exports
  var React = require('react')
  var h = React.createElement

  var rootCtx = null

  function serviceLocale() {
    try {
      var l = rootCtx && rootCtx.locale
      if (!l) return null
      var cands = [l.preference, l.language, l.current, l.lang, l.locale, l.id, l.activeLanguage]
      for (var i = 0; i < cands.length; i += 1) {
        var v = cands[i]
        if (typeof v === 'function') { try { v = v.call(l) } catch (e) { v = null } }
        if (v && typeof v.get === 'function') { try { v = v.get() } catch (e) { } }
        if (typeof v === 'string' && /^(zh|en)/i.test(v)) return v
        if (v && typeof v === 'object') {
          var inner = v.preference || v.language || v.id
          if (typeof inner === 'string' && /^(zh|en)/i.test(inner)) return inner
        }
      }
    } catch (e) { }
    return null
  }

  function detectLang() {
    var sl = serviceLocale()
    if (sl) return /^zh/i.test(sl) ? 'zh' : 'en'

    var htmlLang = (document.documentElement.lang || '').toLowerCase()
    if (/^zh/i.test(htmlLang)) return 'zh'
    if (/^en/i.test(htmlLang)) return 'en'

    try {
      for (var i = 0; i < localStorage.length; i += 1) {
        var k = localStorage.key(i)
        if (k && /locale|lang/i.test(k)) {
          var val = localStorage.getItem(k)
          if (typeof val === 'string' && /zh/i.test(val)) return 'zh'
          if (typeof val === 'string' && /en/i.test(val)) return 'en'
        }
      }
    } catch (e) { }

    var nav = (navigator.language || '').toLowerCase()
    return /^zh/i.test(nav) ? 'zh' : 'en'
  }

  function T(zh, en) {
    return detectLang() === 'zh' ? zh : en
  }

  function detectTheme() {
    var d = document.documentElement
    if (d.classList.contains('dark') || d.getAttribute('data-theme') === 'dark') return 'dark'
    if (d.classList.contains('light') || d.getAttribute('data-theme') === 'light') return 'light'
    try {
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) return 'dark'
    } catch (e) { }
    return 'dark'
  }

  function showError(msg) {
    console.warn('[dsh-screenshot]', msg)
    try {
      var existing = document.querySelector('.dsh-shot-toast')
      if (existing) existing.remove()
      var toast = document.createElement('div')
      toast.className = 'dsh-shot-toast'
      toast.textContent = msg
      document.body.appendChild(toast)
      setTimeout(function() {
        toast.classList.add('fade-out')
        setTimeout(function() { toast.remove() }, 300)
      }, 4000)
    } catch (e) { }
  }

  function ScissorsIcon() {
    return h('svg', {
      width: '18',
      height: '18',
      viewBox: '0 0 24 24',
      fill: 'none',
      stroke: '#8a8f98',
      strokeWidth: '2',
      strokeLinecap: 'round',
      strokeLinejoin: 'round',
      style: {
        display: 'block',
        width: '18px',
        height: '18px',
        flex: 'none'
      }
    },
      h('circle', { cx: '6', cy: '6', r: '3' }),
      h('circle', { cx: '6', cy: '18', r: '3' }),
      h('line', { x1: '20', y1: '4', x2: '8.12', y2: '15.88' }),
      h('line', { x1: '14.47', y1: '14.48', x2: '20', y2: '20' }),
      h('line', { x1: '8.12', y1: '8.12', x2: '12', y2: '12' })
    )
  }

  function collectProbe(btn) {
    if (!btn) return null
    var btnRect = null
    try {
      var r = btn.getBoundingClientRect()
      btnRect = { x: r.x, y: r.y, w: r.width, h: r.height }
    } catch (e) { }

    var btnComputed = {}
    try {
      if (typeof window !== 'undefined' && window.getComputedStyle) {
        var cs = window.getComputedStyle(btn)
        btnComputed = {
          color: cs.color,
          opacity: cs.opacity,
          visibility: cs.visibility,
          display: cs.display,
          width: cs.width,
          height: cs.height,
          overflow: cs.overflow
        }
      }
    } catch (e) { }

    var svgEl = btn.querySelector ? btn.querySelector('svg') : null
    var svgInfo = {
      present: !!svgEl,
      display: '',
      stroke: '',
      width: '',
      height: '',
      getBoundingClientRect: null,
      computedStroke: ''
    }
    if (svgEl) {
      try {
        svgInfo.display = (svgEl.style && svgEl.style.display) || (svgEl.getAttribute && svgEl.getAttribute('display')) || ''
        svgInfo.stroke = (svgEl.style && svgEl.style.stroke) || (svgEl.getAttribute && svgEl.getAttribute('stroke')) || ''
        svgInfo.width = (svgEl.style && svgEl.style.width) || (svgEl.getAttribute && svgEl.getAttribute('width')) || ''
        svgInfo.height = (svgEl.style && svgEl.style.height) || (svgEl.getAttribute && svgEl.getAttribute('height')) || ''
      } catch (e) { }

      try {
        var sr = svgEl.getBoundingClientRect()
        svgInfo.getBoundingClientRect = { x: sr.x, y: sr.y, w: sr.width, h: sr.height }
      } catch (e) { }

      try {
        if (typeof window !== 'undefined' && window.getComputedStyle) {
          var scs = window.getComputedStyle(svgEl)
          svgInfo.computedStroke = scs.stroke || ''
        }
      } catch (e) { }
    }

    var svgChildCount = 0
    try {
      if (svgEl) {
        svgChildCount = svgEl.children ? svgEl.children.length : (svgEl.childNodes ? svgEl.childNodes.length : 0)
      }
    } catch (e) { }

    var styleTagPresent = false
    try {
      styleTagPresent = !!(document.getElementById && document.getElementById('dsh-screenshot-v2-style'))
    } catch (e) { }

    var themeStr = ''
    try {
      var docEl = document.documentElement || {}
      var bodyEl = document.body || {}
      var dTheme = (docEl.getAttribute && docEl.getAttribute('data-theme')) || ''
      themeStr = (docEl.className || '') + ' | ' + dTheme + ' | ' + (bodyEl.className || '')
    } catch (e) { }

    var uaStr = ''
    try {
      uaStr = (typeof navigator !== 'undefined' && navigator.userAgent) || ''
    } catch (e) { }

    return {
      rect: btnRect,
      computed: btnComputed,
      svg: svgInfo,
      svgChildCount: svgChildCount,
      styleTagPresent: styleTagPresent,
      theme: themeStr,
      ua: uaStr
    }
  }

  // F-15: the paste event has to land on the real composer. Falling back to document.body
  // "succeeds" silently and the screenshot then vanishes, so the helpers below report failure
  // and the caller shows an error instead of pretending the picture went in.
  var COMPOSER_SELECTORS = [
    'textarea[data-dsh-composer]',
    'div[data-dsh-composer]',
    '[contenteditable="true"][data-dsh-composer]',
    'textarea[placeholder*="输入"]',
    'textarea[placeholder*="message"]',
    'textarea[placeholder*="Message"]',
    'textarea[placeholder*="Ask"]',
    '.composer textarea',
    '.composer [contenteditable="true"]',
    'div[contenteditable="true"]'
  ]

  function findComposer() {
    for (var i = 0; i < COMPOSER_SELECTORS.length; i += 1) {
      var el = document.querySelector(COMPOSER_SELECTORS[i])
      if (!el || !el.isConnected) continue
      if (el.disabled) continue
      return el
    }
    return null
  }

  function injectImageIntoComposer(base64Data, filename) {
    var target = findComposer()
    if (!target) return false
    try {
      var byteCharacters = atob(base64Data)
      var byteNumbers = new Array(byteCharacters.length)
      for (var i = 0; i < byteCharacters.length; i++) {
        byteNumbers[i] = byteCharacters.charCodeAt(i)
      }
      var byteArray = new Uint8Array(byteNumbers)
      var blob = new Blob([byteArray], { type: 'image/png' })
      var file = new File([blob], filename || 'screenshot.png', { type: 'image/png' })

      var dt = new DataTransfer()
      dt.items.add(file)
      var pasteEvt = new ClipboardEvent('paste', {
        clipboardData: dt,
        bubbles: true,
        cancelable: true
      })
      target.dispatchEvent(pasteEvt)
      return true
    } catch (e) {
      console.error('[dsh-screenshot] Failed to inject image into composer:', e)
      return false
    }
  }

  function sleep(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms) })
  }

  // A failure coming back from the native side is English-only; a failure raised here is
  // already bilingual. Prefix only the former so the user never reads a mixed sentence.
  function showFailure(msg) {
    var text = String(msg || '')
    if (/[^\x00-\x7F]/.test(text)) showError(text)
    else showError(T('截图失败：', 'Screenshot failed: ') + text)
  }

  // Waits for the native session to finish. /shot/api/state reports the outcome, so a
  // cancelled overlay frees the button immediately instead of after a two minute timeout.
  // F-16: polling backs off (400ms -> 2s, ~4 minutes total) and stops on the first error
  // either side reports; the old "watch the PNG mtime" protocol is gone because the state
  // file is the single source of truth.
  function pollSession(initialAt, onFailure, onDone) {
    var delay = 400
    var attempts = 0
    var maxAttempts = 240
    var stopped = false

    async function injectWhenReady(base64Data) {
      if (injectImageIntoComposer(base64Data, 'screenshot.png')) return true
      // The composer can still be mounting right after the overlay closes: try once more.
      await sleep(400)
      return injectImageIntoComposer(base64Data, 'screenshot.png')
    }

    async function loop() {
      while (!stopped && attempts < maxAttempts) {
        attempts += 1
        try {
          var res = await fetch('/shot/api/state', { cache: 'no-store' })
          var st = res && res.ok ? await res.json() : null
          if (st && st.at && st.at !== initialAt) {
            stopped = true
            if (st.error) {
              if (onFailure) onFailure(String(st.error))
              break
            }
            if (st.result === 'ok') {
              var json = await fetch('/shot/api/last', { cache: 'no-store' })
                .then(function(r) { return r.ok ? r.json() : {} })
                .catch(function() { return {} })
              if (json && json.error) {
                if (onFailure) onFailure(String(json.error))
              } else if (json && json.data) {
                var injected = await injectWhenReady(json.data)
                if (!injected && onFailure) {
                  onFailure(T(
                    '截图已生成，但没能插入输入区：找不到会话输入框，请点一下输入框后重试。',
                    'Screenshot captured but the composer was not found; click the composer and try again.'
                  ))
                }
              }
            }
            break
          }
        } catch (e) {
          // transient network error: keep polling with backoff
        }
        await sleep(delay)
        delay = Math.min(Math.round(delay * 1.5), 2000)
      }
      if (!stopped && attempts >= maxAttempts && onFailure) {
        onFailure(T('截图会话超时，请重试。', 'Screenshot session timed out, try again.'))
      }
      if (onDone) onDone()
    }

    loop()
    return function() { stopped = true }
  }

  function ShotButton() {
    var busyState = React.useState(false)
    var busy = busyState[0]
    var setBusy = busyState[1]

    var btnRef = React.useRef ? React.useRef(null) : { current: null }
    if (React.useEffect) {
      React.useEffect(function() {
        var timer = setTimeout(function() {
          try {
            var btn = (btnRef && btnRef.current) || (typeof document !== 'undefined' && document.querySelector && document.querySelector('button[data-dsh-shot="1"]'))
            if (!btn) return
            var probeData = collectProbe(btn)
            if (!probeData) return
            if (typeof fetch === 'function') {
              fetch('/shot/api/probe', {
                method: 'POST',
                headers: { 'content-type': 'application/json' },
                body: JSON.stringify(probeData)
              }).catch(function(err) {
                console.warn('[dsh-screenshot] probe report failed:', err)
              })
            }
          } catch (e) {
            console.warn('[dsh-screenshot] probe error:', e)
          }
        }, 800)
        return function() { clearTimeout(timer) }
      }, [])
    }

    // Left-click opens the overlay WITHOUT hiding DSH; right-click opens it with DSH hidden.
    // "hide" travels with the request so the native side needs no settings file any more.
    var startCapture = async function(hide) {
      if (busy) return
      setBusy(true)
      try {
        // Remember the outcome marker of the previous session: the native side bumps it
        // when this one ends, whether the user confirmed or cancelled. The picture itself is
        // only fetched once that marker moves, so a stale PNG is never injected twice.
        var stRes0 = await fetch('/shot/api/state', { cache: 'no-store' }).catch(function() { return null })
        var st0 = stRes0 && stRes0.ok ? await stRes0.json().catch(function() { return {} }) : {}
        var initialAt = (st0 && st0.at) || 0

        // hide=false -> the overlay leaves DSH on screen (left click);
        // hide=true  -> the overlay hides DSH first and restores it when the session ends.
        var res = await fetch('/shot/api/capture', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            theme: detectTheme(),
            lang: detectLang(),
            hide: !!hide
          })
        })

        if (!res.ok) {
          showError(T('截图服务不可用 (' + res.status + ')', 'Screenshot service unavailable (' + res.status + ')'))
          setBusy(false)
          return
        }

        var data = await res.json().catch(function() { return {} })
        if (data && data.error) {
          showError(data.error)
          setBusy(false)
          return
        }

        // The poll does the fetch, the injection and the failure reporting in one place;
        // onDone always runs, so a cancelled or failed session frees the button immediately.
        pollSession(
          initialAt,
          showFailure,
          function() {
            setBusy(false)
          }
        )
      } catch (err) {
        showError(T(
          '截图工具未就绪或无法连接到 DSH 服务',
          'Screenshot tool not ready or cannot connect to DSH service'
        ))
        setBusy(false)
      }
    }

    var handleClick = function() { return startCapture(false) }
    var handleContextMenu = function(e) {
      if (e && typeof e.preventDefault === 'function') e.preventDefault()
      if (e && typeof e.stopPropagation === 'function') e.stopPropagation()
      return startCapture(true)
    }

    var tip = T('左键保留窗口，右键最小化窗口', 'Left-click: keep window · Right-click: minimize window')

    var btnStyle = {
      width: '32px',
      height: '32px',
      minWidth: '32px',
      flex: 'none',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '0',
      border: 'none',
      background: 'transparent',
      borderRadius: '8px',
      cursor: busy ? 'wait' : 'pointer'
    }

    return h('button', {
      ref: btnRef,
      type: 'button',
      className: 'shot-btn' + (busy ? ' is-busy' : ''),
      style: btnStyle,
      'data-dsh-shot': '1',
      title: tip,
      'aria-label': tip,
      onClick: handleClick,
      onContextMenu: handleContextMenu,
      disabled: busy
    },
      h(ScissorsIcon, null)
    )
  }

  function injectStyles() {
    if (document.getElementById('dsh-screenshot-v2-style')) return
    var style = document.createElement('style')
    style.id = 'dsh-screenshot-v2-style'
    style.textContent = [
      '.shot-btn {',
      '  display: inline-flex;',
      '  align-items: center;',
      '  justify-content: center;',
      '  width: 32px;',
      '  height: 32px;',
      '  min-width: 32px;',
      '  padding: 0;',
      '  border: none;',
      '  border-radius: 8px;',
      '  background: transparent;',
      '  background-repeat: no-repeat;',
      '  background-position: center;',
      '  background-size: 18px 18px;',
      '  cursor: pointer;',
      '  transition: background 0.15s ease;',
      '  flex: none;',
      '}',
      '.shot-btn:hover {',
      '  background: var(--dsw-alias-interactive-bg-hover, var(--color-fill-secondary, rgba(128, 128, 128, 0.15)));',
      '}',
      '.shot-btn:hover svg {',
      '  stroke: #5b6169;',
      '}',
      '.shot-btn.is-busy {',
      '  opacity: 0.6;',
      '  cursor: wait;',
      '}',
      'html.dark .shot-btn:hover, [data-theme="dark"] .shot-btn:hover {',
      '  background: var(--dsw-alias-interactive-bg-hover, var(--color-fill-secondary, rgba(255, 255, 255, 0.08)));',
      '}',
      'html.dark .shot-btn:hover svg, [data-theme="dark"] .shot-btn:hover svg {',
      '  stroke: #cfd3d6;',
      '}',
      '.dsh-shot-toast {',
      '  position: fixed;',
      '  bottom: 80px;',
      '  right: 24px;',
      '  z-index: 999999;',
      '  background: var(--dsw-elevation-surface-overlay, var(--color-bg-elevated, #2a2a2c));',
      '  color: var(--dsw-alias-label-primary, var(--color-text-primary, #ffffff));',
      '  border: 1px solid var(--dsw-alias-border-l2, var(--color-border, rgba(255, 255, 255, 0.15)));',
      '  border-radius: 8px;',
      '  padding: 8px 16px;',
      '  font-size: 13px;',
      '  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);',
      '  transition: opacity 0.3s ease;',
      '}',
      '.dsh-shot-toast.fade-out {',
      '  opacity: 0;',
      '}'
    ].join('\n')
    document.head.appendChild(style)
  }

  // Cordis refuses to read an undeclared service: `ctx.slots` throws
  // "cannot get property \"slots\" without inject", which aborted apply() and failed the whole
  // client entry at web boot ("web boot: 1 entry did not activate" / "dsh-screenshot: failed").
  // `locale` stays optional: serviceLocale() reads it inside try/catch.
  exports.inject = ['slots']

  exports.apply = function(ctx) {
    rootCtx = ctx
    injectStyles()

    // `slots.inject(key, callback)` is an EFFECT api, not a descriptor api: the second argument is
    // installed through ctx.effect() and must be a function that RETURNS the disposer(s) produced by
    // slots.register(options, Component). A plain object here would throw inside ctx.effect().
    //
    // options.name repeats the slot key, options.id is the registration id, and the component is the
    // second argument of register().
    if (ctx.slots && typeof ctx.slots.inject === 'function' && typeof ctx.slots.register === 'function') {
      var slots = ctx.slots

      // `conversation.input.activity` is a SINGLE slot: the voice-input button already holds its only
      // registration, and a second one throws ("single slot ... already has a registration at
      // priority 0"). Registering with a lower priority would *shadow* the microphone button, so this
      // plugin only uses the multi-entry `conversation.input.right` row.
      slots.inject('conversation.input.right', function() {
        return slots.register({
          name: 'conversation.input.right',
          id: 'shot-action',
          order: 100
        }, function ShotActionFallback() {
          return h(ShotButton, null)
        })
      })
    }
  }

  return module.exports
}})
