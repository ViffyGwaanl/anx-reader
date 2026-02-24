// Translation modes
export const TranslationMode = {
  OFF: 'off',
  TRANSLATION_ONLY: 'translation-only', 
  ORIGINAL_ONLY: 'original-only',
  BILINGUAL: 'bilingual'
}

// Make TranslationMode globally available for debugging
if (typeof window !== 'undefined') {
  window.TranslationMode = TranslationMode
}

// Translation function that calls Flutter's translation service
const translate = async (text) => {
  try {
    const result = await window.flutter_inappwebview.callHandler('translateText', text)
    // On failure, return empty string and let the app HUD show failures.
    // Do NOT inject failure messages into the book content.
    return result || ''
  } catch (error) {
    console.error('Translation failed:', error)
    return ''
  }
}

// Rich-text translation for paragraphs containing links.
// Input payload:
// { fullText: string, segments: [{type:'text'|'link', text:string, href?:string}] }
// Output: string[] translations aligned to segments (plain text only)
const translateRichSegments = async (payload) => {
  try {
    const result = await window.flutter_inappwebview.callHandler('translateRichSegments', payload)
    return result
  } catch (error) {
    console.warn('translateRichSegments failed:', error)
    return null
  }
}

export class Translator {
  #translationMode = TranslationMode.OFF
  observedElements = new Set()
  #translatedElements = new WeakMap()
  #translatingElements = new WeakSet()

  // Retry state for elements that failed while staying in the viewport.
  // WeakMap avoids leaks (as long as we don't keep strong refs elsewhere).
  // NOTE: observedElements is a strong Set, so we also prune disconnected nodes.
  #failedElements = new WeakMap()
  #retryTimers = new WeakMap()

  #observer = null
  
  constructor() {
    this.#initializeObserver()
  }

  #initializeObserver() {
    this.#observer = new IntersectionObserver(
      (entries) => {
        if (this.#translationMode === TranslationMode.OFF) return
        // If anything intersects, translate the current + next viewport.
        if (entries.some((e) => e.isIntersecting)) {
          this.forceTranslateForViewport().catch((error) => {
            console.warn('Translation failed in observer:', error)
          })
        }
      },
      {
        // Only translate current viewport + the next viewport.
        // Avoid multi-screen prefetch to reduce API storms.
        rootMargin: '0px 0px 100% 0px',
        threshold: 0
      }
    )
  }

  async setTranslationMode(mode) {
    if (!Object.values(TranslationMode).includes(mode)) {
      console.warn(`Invalid translation mode: ${mode}`)
      return
    }
    
    const oldMode = this.#translationMode
    this.#translationMode = mode
    
    if (oldMode !== mode) {
      // console.log(`Translation mode changed from ${oldMode} to ${mode}`)

      if (mode === TranslationMode.OFF) {
        // Turn off translation
        this.#updateTranslationDisplay()
      } else {
        // When enabling or switching mode, always try to translate the current
        // viewport (and next viewport).
        this.#updateTranslationDisplay()
        await this.forceTranslateForViewport()
      }
    }

    // Re-render annotations after translation mode change (and after translation completion)
    if (window.reader && window.reader.annotationsByValue) {
      const existingAnnotations = Array.from(window.reader.annotationsByValue.values())
      if (existingAnnotations.length > 0) {
        // console.log('Re-rendering annotations after translation mode change:', existingAnnotations.length)
        window.renderAnnotations(existingAnnotations)
      }
    }
  }

  getTranslationMode() {
    return this.#translationMode
  }

  observeDocument(doc) {
    // console.log('Observing document for translation, doc:', doc)
    if (!doc) {
      console.warn('No document provided to observeDocument')
      return
    }

    this.#pruneDisconnectedElements()

    const textElements = this.#walkTextNodes(doc.body || doc.documentElement)
    // console.log(`Found ${textElements.length} text elements to observe`)

    textElements.forEach(element => {
      if (!this.observedElements.has(element)) {
        this.#observer.observe(element)
        this.observedElements.add(element)
        // console.log('Added element to observer:', element.tagName, element.textContent?.substring(0, 50))
      }
    })

    // console.log(`Total observed elements: ${this.observedElements.size}`)
  }

  #pruneDisconnectedElements() {
    // observedElements is a strong Set. Remove elements that are no longer in
    // the DOM to avoid memory growth across relocations/chapters.
    for (const el of Array.from(this.observedElements)) {
      try {
        if (!el || !el.isConnected) {
          this.observedElements.delete(el)
        }
      } catch (_) {
        this.observedElements.delete(el)
      }
    }
  }

  clearTranslations() {
    // Remove all translation elements and restore original content
    this.observedElements.forEach(element => {
      const translationElements = element.querySelectorAll('.translated-text')
      translationElements.forEach(trans => trans.remove())
      
      // Restore original text if hidden
      this.#restoreOriginalText(element)
    })
    
    // Clear observer
    this.#observer.disconnect()
    this.observedElements.clear()
    this.#translatedElements = new WeakMap()
    this.#failedElements = new WeakMap()
    this.#retryTimers = new WeakMap()
    
    // Reinitialize observer
    this.#initializeObserver()
  }

  #walkTextNodes(root, rejectTags = ['pre', 'code', 'math', 'style', 'script']) {
    // IMPORTANT: For EPUB reading, translating inline nodes (e.g. SPAN) causes
    // partial/mixed results within a paragraph.
    // We prefer block-level elements as translation units.

    if (!root || !root.querySelectorAll) return []

    const blockSelectors = [
      'p',
      'li',
      'blockquote',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'figcaption',
      'dd', 'dt',
    ]

    const candidates = Array.from(root.querySelectorAll(blockSelectors.join(',')))

    const isRejected = (el) => {
      const name = el.tagName.toLowerCase()
      if (rejectTags.includes(name)) return true
      if (el.classList && el.classList.contains('translated-text')) return true
      if (el.closest && el.closest('.translated-text')) return true
      return false
    }

    const elements = []

    for (const el of candidates) {
      if (!el || isRejected(el)) continue

      // Skip list items that already contain paragraphs: let <p> be the unit.
      if (el.tagName.toLowerCase() === 'li') {
        if (el.querySelector('p')) continue
      }

      // Skip empty blocks.
      const text = el.innerText?.trim() || el.textContent?.trim()
      if (!text) continue

      elements.push(el)
    }

    return elements
  }

  #extractLinkSegments(element) {
    const segments = []

    const walk = (node) => {
      if (!node) return

      if (node.nodeType === Node.TEXT_NODE) {
        const t = node.textContent || ''
        if (t) segments.push({ type: 'text', text: t })
        return
      }

      if (node.nodeType === Node.ELEMENT_NODE) {
        const el = node
        const name = (el.tagName || '').toLowerCase()

        if (name === 'a' && el.getAttribute && el.getAttribute('href')) {
          segments.push({
            type: 'link',
            href: el.getAttribute('href'),
            text: el.textContent || ''
          })
          return
        }

        // Flatten other inline nodes.
        const children = Array.from(el.childNodes || [])
        for (const c of children) walk(c)
      }
    }

    for (const c of Array.from(element.childNodes || [])) {
      walk(c)
    }

    return segments
  }

  async #translateElement(element, { force = false } = {}) {
    if (this.#translationMode === TranslationMode.OFF) return
    if (!element || !element.isConnected) return
    if (this.#translatedElements.has(element)) return
    if (this.#translatingElements.has(element)) return

    const failState = this.#failedElements.get(element)
    if (!force && failState && failState.attempts >= 6) {
      return
    }

    if (force) {
      // Manual retry should not be blocked by previous failures.
      try {
        this.#clearFailure(element)
      } catch (_) {}
    }

    const text = element.innerText?.trim()
    if (!text) return

    this.#translatingElements.add(element)

    try {
      const hasLink = element.querySelector && element.querySelector('a[href]')

      if (hasLink) {
        const segments = this.#extractLinkSegments(element)
        if (segments && segments.length > 0) {
          const translatedSegments = await translateRichSegments({
            fullText: text,
            segments
          })

          if (translatedSegments && Array.isArray(translatedSegments) && translatedSegments.length === segments.length) {
            const joined = translatedSegments.join('')
            if (joined && joined.trim()) {
              // Mark as translated to prevent re-processing
              this.#translatedElements.set(element, {
                originalText: text,
                translatedText: joined,
                structuredLinks: true,
              })

              this.#clearFailure(element)
              this.#applyStructuredTranslation(element, segments, translatedSegments)
              return
            }
          }
        }
      }

      const translatedText = await translate(text)

      // Empty translation -> failure: schedule retry if still in viewport.
      if (!translatedText || !translatedText.trim()) {
        this.#markFailure(element)
        this.#scheduleRetryIfVisible(element)
        return
      }

      // Mark as translated to prevent re-processing
      this.#translatedElements.set(element, {
        originalText: text,
        translatedText: translatedText
      })

      this.#clearFailure(element)
      this.#applyTranslation(element, translatedText)
    } catch (error) {
      this.#markFailure(element)
      this.#scheduleRetryIfVisible(element)
      console.warn('Translation failed:', error)
    } finally {
      this.#translatingElements.delete(element)
    }
  }

  #markFailure(element) {
    try {
      const prev = this.#failedElements.get(element) || { attempts: 0, lastAt: 0 }
      const next = {
        attempts: (prev.attempts || 0) + 1,
        lastAt: Date.now(),
      }
      this.#failedElements.set(element, next)
      try {
        element.setAttribute('data-translation-failed', String(next.attempts))
      } catch (_) {}
    } catch (_) {
      // ignore
    }
  }

  #clearFailure(element) {
    try {
      this.#failedElements.delete(element)
      const timer = this.#retryTimers.get(element)
      if (timer) {
        clearTimeout(timer)
        this.#retryTimers.delete(element)
      }
      try {
        element.removeAttribute('data-translation-failed')
      } catch (_) {}
    } catch (_) {}
  }

  #scheduleRetryIfVisible(element) {
    if (this.#translationMode === TranslationMode.OFF) return
    if (!element || !element.isConnected) return
    if (this.#translatedElements.has(element)) return
    if (this.#translatingElements.has(element)) return

    const state = this.#failedElements.get(element)
    if (!state) return
    if (state.attempts >= 6) return

    // Avoid multiple timers per element.
    if (this.#retryTimers.get(element)) return

    // Only retry if the element is within current+next viewport.
    try {
      const rect = element.getBoundingClientRect()
      if (!rect) return
      if (rect.bottom <= 0) return
      if (rect.top > window.innerHeight * 2) return

      const attempt = state.attempts || 1
      const delay = Math.min(8000, 600 * Math.pow(2, Math.max(0, attempt - 1)))

      const timer = setTimeout(() => {
        try {
          this.#retryTimers.delete(element)
        } catch (_) {}
        // Retry only if still relevant.
        if (this.#translationMode === TranslationMode.OFF) return
        if (!element || !element.isConnected) return
        if (this.#translatedElements.has(element)) return
        if (this.#translatingElements.has(element)) return
        this.#translateElement(element).catch((e) => {
          console.warn('Retry translation failed:', e)
        })
      }, delay)

      this.#retryTimers.set(element, timer)
    } catch (_) {
      // ignore
    }
  }

  #applyStructuredTranslation(element, segments, translatedSegments) {
    const existingTranslation = element.querySelector('.translated-text')
    if (existingTranslation) {
      existingTranslation.remove()
    }

    const wrapper = document.createElement('span')
    wrapper.className = 'translated-text'
    wrapper.setAttribute('data-translation-mark', '1')
    wrapper.style.display = 'block'
    wrapper.style.marginTop = '0.2em'

    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i]
      const t = (translatedSegments[i] || '')

      if (!seg || !seg.type) {
        wrapper.appendChild(document.createTextNode(t))
        continue
      }

      if (seg.type === 'link' && seg.href) {
        const a = document.createElement('a')
        a.setAttribute('href', seg.href)
        a.textContent = t

        // Make translated links work with the reader's navigation.
        a.addEventListener('click', (e) => {
          e.preventDefault()
          e.stopPropagation()
          try {
            if (typeof window.goToHref === 'function') {
              window.goToHref(seg.href)
              return
            }
          } catch (_) {}
          try {
            window.location.href = seg.href
          } catch (_) {}
        }, true)

        wrapper.appendChild(a)
      } else {
        wrapper.appendChild(document.createTextNode(t))
      }
    }

    this.#updateElementDisplay(element, wrapper)
    element.appendChild(wrapper)
  }

  #applyTranslation(element, translatedText) {
    // Remove existing translation if any
    const existingTranslation = element.querySelector('.translated-text')
    if (existingTranslation) {
      existingTranslation.remove()
    }

    // Create translation wrapper
    const wrapper = document.createElement('span')
    wrapper.className = 'translated-text'
    wrapper.setAttribute('data-translation-mark', '1')
    wrapper.style.display = 'block'
    wrapper.style.marginTop = '0.2em'
    wrapper.textContent = translatedText

    // Apply based on current mode
    this.#updateElementDisplay(element, wrapper)

    element.appendChild(wrapper)
  }

  #updateElementDisplay(element, translationWrapper) {
    const data = this.#translatedElements.get(element)
    if (!data) return

    const wrapperHasLinks = !!(translationWrapper && translationWrapper.querySelector && translationWrapper.querySelector('a[href]'))

    switch (this.#translationMode) {
      case TranslationMode.TRANSLATION_ONLY:
        // If the translation wrapper already contains links, we can safely hide
        // original link subtrees. Otherwise, preserve original links.
        this.#hideOriginalText(element, { preserveLinks: !wrapperHasLinks })
        translationWrapper.style.display = 'block'
        break
        
      case TranslationMode.ORIGINAL_ONLY:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break
        
      case TranslationMode.BILINGUAL:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'block'
        break
        
      case TranslationMode.OFF:
      default:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break
    }
  }

  #hideOriginalText(element, { preserveLinks = true } = {}) {
    // Use CSS to hide original content instead of removing DOM nodes
    if (!element.hasAttribute('data-original-visibility')) {
      element.setAttribute('data-original-visibility', 'hidden')

      Array.from(element.childNodes).forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (el.classList && el.classList.contains('translated-text')) {
            return
          }

          if (preserveLinks) {
            const containsLink =
              (el.matches && el.matches('a[href]')) ||
              (el.querySelector && el.querySelector('a[href]'))

            if (containsLink) {
              // Do not hide; keep link subtree interactive.
              return
            }
          }

          // Store and hide using CSS
          if (!el.hasAttribute('data-original-display')) {
            el.setAttribute('data-original-display', el.style.display || 'initial')
            el.style.display = 'none'
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          if (preserveLinks) {
            const parent = node.parentElement
            const inLink = parent && parent.closest && parent.closest('a[href]')
            if (inLink) return
          }

          if (!node.__originalContent) {
            node.__originalContent = node.textContent
            node.textContent = ''
          }
        }
      })
    }

    // Mark element as having hidden text
    element.classList.add('translation-source-hidden')
  }

  #restoreOriginalText(element) {
    // Restore visibility by reversing the hide operations
    if (element.hasAttribute('data-original-visibility')) {
      // Restore all child nodes
      Array.from(element.childNodes).forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (!el.classList || !el.classList.contains('translated-text')) {
            // Restore original display
            if (el.hasAttribute('data-original-display')) {
              const originalDisplay = el.getAttribute('data-original-display')
              el.style.display = originalDisplay === 'initial' ? '' : originalDisplay
              el.removeAttribute('data-original-display')
            }
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          // Restore text content
          if (node.__originalContent !== undefined) {
            node.textContent = node.__originalContent
            delete node.__originalContent
          }
        }
      })
      
      element.removeAttribute('data-original-visibility')
    }
    
    element.classList.remove('translation-source-hidden')
  }

  async forceTranslateForViewport() {
    return this.#forceTranslateVisibleElements({ force: false })
  }

  async forceRetryForViewport() {
    // Manual retry: reset failure state for visible elements and ignore retry cap.
    return this.#forceTranslateVisibleElements({ force: true, resetFailures: true })
  }

  async #forceTranslateVisibleElements({ force = false, resetFailures = false } = {}) {
    // Prioritize current viewport first, then next viewport.
    // Also limit the number of newly-started translations to reduce backlog
    // when the user scrolls quickly.

    this.#pruneDisconnectedElements()

    const currentBottom = window.innerHeight
    const prefetchBottom = window.innerHeight * 2

    const current = []
    const next = []

    this.observedElements.forEach((element) => {
      if (!element || !element.getBoundingClientRect) return

      const rect = element.getBoundingClientRect()
      if (rect.bottom <= 0) return

      // If we have a translation state but the DOM wrapper is missing (e.g. DOM
      // got re-rendered), treat it as NOT translated so it can be re-generated.
      if (rect.top < prefetchBottom && this.#translatedElements.has(element)) {
        const translationWrapper = element.querySelector('.translated-text')
        if (translationWrapper) {
          this.#updateElementDisplay(element, translationWrapper)
          return
        }

        // Missing wrapper: drop state so it can be translated again.
        this.#translatedElements.delete(element)
      }

      // Skip already translated/inflight
      if (this.#translatedElements.has(element)) return
      if (this.#translatingElements.has(element)) return

      // Current viewport
      if (rect.top < currentBottom) {
        current.push({ element, top: rect.top })
        return
      }

      // Next viewport
      if (rect.top < prefetchBottom) {
        next.push({ element, top: rect.top })
      }
    })

    current.sort((a, b) => a.top - b.top)
    next.sort((a, b) => a.top - b.top)

    const maxStartTotal = 12
    const maxStartCurrent = 8

    const candidates = current.length + next.length

    let started = 0

    const startOne = (item) => {
      started++

      if (resetFailures) {
        try {
          this.#clearFailure(item.element)
        } catch (_) {}
      }

      // Start but don't await (Flutter side enforces concurrency).
      this.#translateElement(item.element, { force }).catch((error) => {
        console.warn('Force translation failed:', error)
      })
    }

    for (const item of current) {
      if (started >= maxStartTotal) break
      if (started >= maxStartCurrent) break
      startOne(item)
    }

    for (const item of next) {
      if (started >= maxStartTotal) break
      startOne(item)
    }

    return {
      started,
      candidates,
      current: current.length,
      next: next.length,
    }
  }

  #updateTranslationDisplay() {
    // console.log('Updating translation display for mode:', this.#translationMode, 'Elements:', this.observedElements.size)
    this.observedElements.forEach(element => {
      const translationWrapper = element.querySelector('.translated-text')
      if (translationWrapper) {
        // console.log('Updating display for element with translation:', element)
        this.#updateElementDisplay(element, translationWrapper)
      } else {
        // console.log('No translation wrapper found for element:', element)
      }
    })
  }

  destroy() {
    this.clearTranslations()
    this.#observer = null
  }
}