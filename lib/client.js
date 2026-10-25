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
      width: '16',
      height: '16',
      viewBox: '0 0 24 24',
      fill: 'none',
      stroke: 'currentColor',
      strokeWidth: '2',
      strokeLinecap: 'round',
      strokeLinejoin: 'round'
    },
      h('circle', { cx: '6', cy: '6', r: '3' }),
      h('circle', { cx: '6', cy: '18', r: '3' }),
      h('line', { x1: '20', y1: '4', x2: '8.12', y2: '15.88' }),
      h('line', { x1: '14.47', y1: '14.48', x2: '20', y2: '20' }),
      h('line', { x1: '8.12', y1: '8.12', x2: '12', y2: '12' })
    )
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
    var btnRef = React.useRef(null)
    var busyState = React.useState(false)
    var busy = busyState[0]
    var setBusy = busyState[1]

    // Ensure the scissors button is inside the same container, immediately before the
    // microphone button. F-16: the observer watches the document only until the composer row
    // shows up, then it narrows to that row; observing all of document.body for the lifetime
    // of a chat page costs a callback on every mutation.
    React.useEffect(function() {
      var observer = null
      var observed = null

      function findMic() {
        return document.querySelector('button[aria-label*="语音"], button[title*="语音"], button[aria-label*="Voice"], button[title*="Voice"]')
      }

      function observe(node, options) {
        if (observed === node) return
        if (observer) observer.disconnect()
        observed = node
        observer = new MutationObserver(function() { alignPosition() })
        observer.observe(node, options)
      }

      function alignPosition() {
        var mic = findMic()
        var btn = btnRef.current
        if (!mic || !btn || !mic.parentElement) {
          observe(document.body, { childList: true, subtree: true })
          return
        }
        if (btn.parentElement !== mic.parentElement || btn.nextElementSibling !== mic) {
          mic.parentElement.insertBefore(btn, mic)
        }
        observe(mic.parentElement, { childList: true })
      }

      alignPosition()
      return function() { if (observer) observer.disconnect() }
    }, [])

    var handleClick = async function() {
      if (busy) return
      setBusy(true)
      try {
        // Remember the outcome marker of the previous session: the native side bumps it
        // when this one ends, whether the user confirmed or cancelled. The picture itself is
        // only fetched once that marker moves, so a stale PNG is never injected twice.
        var stRes0 = await fetch('/shot/api/state', { cache: 'no-store' }).catch(function() { return null })
        var st0 = stRes0 && stRes0.ok ? await stRes0.json().catch(function() { return {} }) : {}
        var initialAt = (st0 && st0.at) || 0

        // The plugin never passes a hide flag: whether the DSH window is concealed belongs to
        // the native settings file. Language/theme are still forwarded to the native process.
        var res = await fetch('/shot/api/capture', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            theme: detectTheme(),
            lang: detectLang()
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

    var tip = T('截图', 'Screenshot')

    return h('button', {
      ref: btnRef,
      type: 'button',
      className: 'shot-btn' + (busy ? ' is-busy' : ''),
      'data-dsh-shot': '1',
      title: tip,
      'aria-label': tip,
      onClick: handleClick,
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
      '  padding: 0;',
      '  border: none;',
      '  border-radius: 8px;',
      '  background: transparent;',
      '  color: var(--color-text-secondary, rgba(255, 255, 255, 0.7));',
      '  cursor: pointer;',
      '  transition: background 0.15s ease, color 0.15s ease;',
      '  flex-shrink: 0;',
      '}',
      '.shot-btn:hover {',
      '  background: var(--color-fill-secondary, rgba(255, 255, 255, 0.08));',
      '  color: var(--color-text-primary, #ffffff);',
      '}',
      '.shot-btn.is-busy {',
      '  opacity: 0.6;',
      '  cursor: wait;',
      '}',
      '.dsh-shot-toast {',
      '  position: fixed;',
      '  bottom: 80px;',
      '  right: 24px;',
      '  z-index: 999999;',
      '  background: var(--color-bg-elevated, #2a2a2c);',
      '  color: var(--color-text-primary, #ffffff);',
      '  border: 1px solid var(--color-border, rgba(255, 255, 255, 0.15));',
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

  exports.apply = function(ctx) {
    rootCtx = ctx
    injectStyles()

    // Primary slot: conversation.input.activity (order: -100 to appear before voice-input-activity)
    if (ctx.slots && typeof ctx.slots.inject === 'function') {
      ctx.slots.inject('conversation.input.activity', {
        id: 'shot-activity',
        order: -100,
        component: ShotButton
      })
      // Fallback slot if activity slot is not mounted
      ctx.slots.inject('conversation.input.right', {
        id: 'shot-action',
        order: 100,
        component: function() {
          // If already rendered in activity container, do not duplicate
          if (document.querySelector('button[data-dsh-shot="1"]')) return null
          return h(ShotButton, null)
        }
      })
    }
  }

  return module.exports
}})
