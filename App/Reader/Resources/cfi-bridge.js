// Dogear's CFI bridge inside each EPUB resource (ADR 0004). Needs window.CFI (epubcfi.js).
// Runs as a WKUserScript: a <script> element would shift the CFI step indices of the page.
(function () {
  const scrollMode = () =>
    document.documentElement.style.getPropertyValue('--USER__view').trim() === 'readium-scroll-on'

  // The in-resource part of a CFI: the package document steps (before `!`) are dropped, as
  // foliate's view.js does once it has picked the resource.
  function rangeOf(cfi) {
    const parts = CFI.parse(cfi)
    ;(parts.parent ?? parts).shift()
    return CFI.toRange(document, parts)
  }

  // First rendered box at or after the range start; element boundaries have no box of their own.
  function firstRect(range) {
    const point = document.createRange()
    point.setStart(range.startContainer, range.startOffset)
    point.collapse(true)
    let rects = Array.from(point.getClientRects()).filter(r => r.width || r.height)
    if (rects.length) return rects[0]
    const start = range.startContainer.nodeType === 1
      ? (range.startContainer.childNodes[range.startOffset] ?? range.startContainer)
      : range.startContainer
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT)
    walker.currentNode = start
    for (let node = start; node; node = walker.nextNode()) {
      if (node.nodeType === 3 && !node.nodeValue.trim()) continue
      if (node.nodeType === 1 && node.localName !== 'img' && node.localName !== 'svg') continue
      const box = document.createRange()
      if (node.nodeType === 1) box.selectNode(node)
      else box.selectNodeContents(node)
      rects = Array.from(box.getClientRects()).filter(r => r.width || r.height)
      if (rects.length) return rects[0]
    }
    return range.getBoundingClientRect()
  }

  // Port of foliate paginator.js getVisibleRange, in viewport coordinates.
  const makeRange = (node, start, end = start) => {
    const range = document.createRange()
    range.setStart(node, start)
    range.setEnd(node, end)
    return range
  }
  const bisectNode = (node, cb, start = 0, end = node.nodeValue.length) => {
    if (end - start === 1) {
      const result = cb(makeRange(node, start), makeRange(node, end))
      return result < 0 ? start : end
    }
    const mid = Math.floor(start + (end - start) / 2)
    const result = cb(makeRange(node, start, mid), makeRange(node, mid, end))
    return result < 0 ? bisectNode(node, cb, start, mid)
      : result > 0 ? bisectNode(node, cb, mid, end) : mid
  }
  const bounds = target => {
    let top = Infinity, right = -Infinity, left = Infinity, bottom = -Infinity
    for (const rect of target.getClientRects()) {
      left = Math.min(left, rect.left); top = Math.min(top, rect.top)
      right = Math.max(right, rect.right); bottom = Math.max(bottom, rect.bottom)
    }
    return new DOMRect(left, top, right - left, bottom - top)
  }
  function getVisibleRange(start, end, mapRect) {
    const acceptNode = node => {
      const name = node.localName?.toLowerCase()
      if (name === 'script' || name === 'style') return NodeFilter.FILTER_REJECT
      if (node.nodeType === 1) {
        const { left, right } = mapRect(node.getBoundingClientRect())
        if (right < start || left > end) return NodeFilter.FILTER_REJECT
        if (left >= start && right <= end) return NodeFilter.FILTER_ACCEPT
      } else {
        if (!node.nodeValue?.trim()) return NodeFilter.FILTER_SKIP
        const range = document.createRange()
        range.selectNodeContents(node)
        const { left, right } = mapRect(range.getBoundingClientRect())
        if (right >= start && left <= end) return NodeFilter.FILTER_ACCEPT
      }
      return NodeFilter.FILTER_SKIP
    }
    const walker = document.createTreeWalker(document.body,
      NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT | NodeFilter.SHOW_CDATA_SECTION, { acceptNode })
    const nodes = []
    for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node)
    const from = nodes[0] ?? document.body
    const to = nodes[nodes.length - 1] ?? from
    const startOffset = from.nodeType === 1 ? 0
      : bisectNode(from, (a, b) => {
        const p = mapRect(bounds(a)), q = mapRect(bounds(b))
        if (p.right < start && q.left > start) return 0
        return q.left > start ? -1 : 1
      })
    const endOffset = to.nodeType === 1 ? 0
      : bisectNode(to, (a, b) => {
        const p = mapRect(bounds(a)), q = mapRect(bounds(b))
        if (p.right < end && q.left > end) return 0
        return q.left > end ? -1 : 1
      })
    const range = document.createRange()
    range.setStart(from, startOffset)
    range.setEnd(to, endOffset)
    return range
  }

  function visibleRange() {
    // foliate maps vertical boxes onto the horizontal axis when scrolling.
    if (scrollMode()) return getVisibleRange(0, window.innerHeight, ({ top, bottom }) => ({ left: top, right: bottom }))
    return getVisibleRange(0, window.innerWidth, rect => rect)
  }

  window.dogearCFI = {
    // How far into this resource (0…1) the CFI's start is, or null if it doesn't resolve here.
    progression(cfi) {
      try {
        const rect = firstRect(rangeOf(cfi))
        const page = document.scrollingElement
        return scrollMode()
          ? (rect.top + window.scrollY) / page.scrollHeight
          : (rect.left + window.scrollX + 1) / page.scrollWidth
      } catch (e) {
        return null
      }
    },
    // The visible range as a CFI, joined to the resource's spine step (e.g. `/6/8[ch2]`).
    visible(spineStep) {
      return CFI.joinIndir(spineStep, CFI.fromRange(visibleRange()))
    },
    // Range ends depend on the viewport, so only starts are compared.
    sameStart(a, b) {
      return CFI.compare(CFI.collapse(a), CFI.collapse(b)) === 0
    },
    collapse(cfi) {
      return CFI.collapse(cfi)
    },
  }
})();
