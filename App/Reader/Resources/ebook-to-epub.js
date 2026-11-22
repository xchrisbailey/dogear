// Converts a MOBI, AZW3 (KF8) or FB2 Book file into an EPUB, so Dogear's EPUB reader can open it.
//
// foliate-js (the parser Grimmory's web reader uses) splits the Book file into sections. Each one
// is written into the EPUB exactly as the web reader displays it, and in the same order, so a CFI
// from either reader points at the same text in the other (docs/reference/readium.md):
// - the spine is the package document's third element and its itemrefs carry no IDs, so spine
//   step N is foliate's `/6/N` for the same section;
// - a section's markup is only changed inside attribute values (resource and link addresses),
//   which CFIs don't count.
import { blobs } from './blob-recorder.js'
import { isMOBI, MOBI } from './mobi.js'
import { makeFB2 } from './fb2.js'
import { unzlibSync } from './fflate.js'

const XHTML = 'application/xhtml+xml'
const HTML = 'text/html'

export const convert = async file => {
    const book = await open(file)
    // One at a time, in reading order: MOBI sections are read from a shared, growing buffer.
    const sections = []
    for (const section of book.sections) sections.push(await loadSection(section))
    const resources = await collectResources(sections.map(section => section.text))
    const targets = new Targets(book, sections)

    const files = []
    for (const [index, section] of sections.entries()) {
        let text = replaceBlobURLs(section.text, resources)
        text = await replaceLinks(text, targets)
        files.push({ name: sectionName(index, section.type), data: text })
    }
    for (const resource of resources.values()) {
        files.push({ name: resource.name, data: resource.text != null ? replaceBlobURLs(resource.text, resources) : resource.bytes })
    }
    files.push({ name: 'nav.xhtml', data: await navigation(book, targets) })
    files.push({ name: 'content.opf', data: packageDocument(book, sections, resources) })
    return zip([
        { name: 'mimetype', data: 'application/epub+zip' },
        { name: 'META-INF/container.xml', data: container },
        ...files,
    ])
}

/**
 * What Dogear's converter calls: fetches `name` from the page's own address and converts it.
 * Answers `{ epub }`, the EPUB in base64, or `{ failure }`: `protected` for a DRM-locked file,
 * `unreadable` for anything else.
 */
export const convertFetched = async name => {
    try {
        const blob = await (await fetch(name)).blob()
        const epub = await convert(new File([blob], name))
        let binary = ''
        for (let start = 0; start < epub.length; start += 0x8000)
            binary += String.fromCharCode(...epub.subarray(start, start + 0x8000))
        return { epub: btoa(binary) }
    } catch (error) {
        console.error(error)
        return { failure: error instanceof ProtectedError ? 'protected' : 'unreadable', message: String(error) }
    }
}

class ProtectedError extends Error {}

/** As foliate's view.js `makeBook` opens them. */
const open = async file => {
    if (await isMOBI(file)) {
        const mobi = new MOBI({ unzlib: unzlibSync })
        let book, failure
        try {
            book = await mobi.open(file)
        } catch (error) {
            failure = error
        }
        // foliate doesn't check, and a locked file's text is noise.
        if (mobi.headers?.palmdoc?.encryption) throw new ProtectedError('DRM-protected')
        if (failure) throw failure
        return book
    }
    if (file.name.endsWith('.fb2')) return makeFB2(file)
    throw new Error('Not a MOBI, AZW3 or FB2 file')
}

/** The section's markup, as the web reader loads it into its page. */
const loadSection = async section => {
    try {
        const blob = blobs.get(await section.load())
        if (blob) return { text: await blob.text(), type: blob.type === HTML ? HTML : XHTML, linear: section.linear }
    } catch (error) {
        console.error(error)
    }
    // Kept, so the sections after it keep their spine steps.
    return { text: emptySection, type: XHTML, linear: section.linear }
}

const emptySection = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title></title></head><body></body></html>'

const sectionName = (index, type) => `section-${index}.${type === HTML ? 'html' : 'xhtml'}`

// MARK: Resources

const blobURLs = /blob:[^"'()\s<>]+/g

/** Every Blob the sections refer to, directly or from a stylesheet, named for the EPUB. */
const collectResources = async texts => {
    const resources = new Map()
    const pending = texts.flatMap(text => [...text.matchAll(blobURLs)].map(match => match[0]))
    while (pending.length) {
        const url = pending.shift()
        if (resources.has(url)) continue
        const blob = blobs.get(url)
        if (!blob) continue
        const bytes = new Uint8Array(await blob.arrayBuffer())
        const kind = kindOf(bytes, blob.type)
        const resource = { name: `resource-${resources.size}.${kind.extension}`, type: kind.type, bytes }
        if (kind.isText) {
            resource.text = new TextDecoder().decode(bytes)
            pending.push(...[...resource.text.matchAll(blobURLs)].map(match => match[0]))
        }
        resources.set(url, resource)
    }
    return resources
}

const replaceBlobURLs = (text, resources) => text.replace(blobURLs, url => resources.get(url)?.name ?? url)

const kinds = {
    jpeg: { type: 'image/jpeg', extension: 'jpg' },
    png: { type: 'image/png', extension: 'png' },
    gif: { type: 'image/gif', extension: 'gif' },
    webp: { type: 'image/webp', extension: 'webp' },
    bmp: { type: 'image/bmp', extension: 'bmp' },
    svg: { type: 'image/svg+xml', extension: 'svg', isText: true },
    woff: { type: 'font/woff', extension: 'woff' },
    woff2: { type: 'font/woff2', extension: 'woff2' },
    otf: { type: 'font/otf', extension: 'otf' },
    ttf: { type: 'font/ttf', extension: 'ttf' },
    css: { type: 'text/css', extension: 'css', isText: true },
    xhtml: { type: XHTML, extension: 'xhtml', isText: true },
    other: { type: 'application/octet-stream', extension: 'bin' },
}

/** MOBI resources come without a type, so they're told apart by their first bytes. */
const kindOf = (bytes, type) => {
    const starts = (...values) => values.every((value, index) => bytes[index] === value)
    const ascii = (offset, text) => [...text].every((character, index) => bytes[offset + index] === character.charCodeAt(0))
    if (starts(0xFF, 0xD8, 0xFF)) return kinds.jpeg
    if (starts(0x89, 0x50, 0x4E, 0x47)) return kinds.png
    if (ascii(0, 'GIF8')) return kinds.gif
    if (ascii(0, 'RIFF') && ascii(8, 'WEBP')) return kinds.webp
    if (ascii(0, 'BM')) return kinds.bmp
    if (ascii(0, 'wOFF')) return kinds.woff
    if (ascii(0, 'wOF2')) return kinds.woff2
    if (ascii(0, 'OTTO')) return kinds.otf
    if (starts(0x00, 0x01, 0x00, 0x00) || ascii(0, 'true')) return kinds.ttf
    if (type === 'text/css') return kinds.css
    if (type === 'image/svg+xml') return kinds.svg
    if (type === XHTML) return kinds.xhtml
    if (bytes.subarray(0, 512).some(byte => byte === 0)) return kinds.other
    const start = new TextDecoder().decode(bytes.subarray(0, 512))
    return /<svg[\s>]/.test(start) ? kinds.svg : kinds.css
}

// MARK: Links

/** Where foliate's links and table of contents entries point, as addresses inside the EPUB. */
class Targets {
    #book
    #sections
    #documents = new Map()

    constructor(book, sections) {
        this.#book = book
        this.#sections = sections
    }

    /** The address `href` points at, or nil when it's outside the Book file or can't be resolved. */
    async address(href) {
        if (this.#isExternal(href)) return null
        let resolved
        try {
            resolved = await this.#book.resolveHref(href)
        } catch {
            return null
        }
        const index = resolved?.index
        const section = this.#sections[index]
        if (!section) return null
        const name = sectionName(index, section.type)
        let target
        try {
            target = resolved.anchor?.(this.#document(index))
        } catch {}
        // Only an ID already in the markup can be pointed at: adding one would change CFIs.
        const id = target?.nodeType === Node.ELEMENT_NODE ? target.id : null
        return id ? `${name}#${encodeURIComponent(id)}` : name
    }

    #isExternal(href) {
        if (/^(blob|data):/i.test(href)) return true
        return this.#book.isExternal?.(href) ?? /^\w+:/i.test(href)
    }

    #document(index) {
        if (!this.#documents.has(index)) {
            const { text, type } = this.#sections[index]
            this.#documents.set(index, new DOMParser().parseFromString(text, type))
        }
        return this.#documents.get(index)
    }
}

const replaceLinks = async (text, targets) => {
    const values = new Set([...text.matchAll(/\shref="([^"]*)"/g)].map(match => match[1]))
    const addresses = new Map()
    for (const value of values) {
        const address = await targets.address(unescapeAttribute(value))
        if (address) addresses.set(value, escapeXML(address))
    }
    return text.replace(/(\shref=")([^"]*)(")/g, (match, before, value, after) =>
        addresses.has(value) ? before + addresses.get(value) + after : match)
}

const unescapeAttribute = value => value
    .replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&amp;/g, '&')

const escapeXML = value => String(value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

// MARK: Package

const container = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`

/** foliate's metadata values are strings, language maps, contributor objects or lists of them. */
const plain = value => {
    if (value == null) return ''
    if (typeof value === 'string') return value
    if (Array.isArray(value)) return value.map(plain).filter(Boolean).join(', ')
    if (typeof value === 'object') return plain(value.name ?? Object.values(value)[0])
    return String(value)
}

const list = value => (Array.isArray(value) ? value : value ? [value] : []).map(plain).filter(Boolean)

const packageDocument = (book, sections, resources) => {
    const metadata = book.metadata ?? {}
    const title = plain(metadata.title) || 'Untitled'
    const language = list(metadata.language)[0] || 'und'
    const identifier = plain(metadata.identifier) || `dogear-${title}`
    const fixedLayout = book.rendition?.layout === 'pre-paginated'
    const manifest = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        ...sections.map((section, index) =>
            `<item id="section-${index}" href="${sectionName(index, section.type)}" media-type="${section.type}"/>`),
        ...[...resources.values()].map((resource, index) =>
            `<item id="resource-${index}" href="${resource.name}" media-type="${resource.type}"/>`),
    ]
    // No IDs on the itemrefs: foliate's CFI spine steps have no ID assertions.
    const spine = sections.map((section, index) =>
        `<itemref idref="section-${index}"${section.linear === 'no' ? ' linear="no"' : ''}/>`)
    const direction = book.dir === 'rtl' ? ' page-progression-direction="rtl"' : ''
    return `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="uid">${escapeXML(identifier)}</dc:identifier>
<dc:title>${escapeXML(title)}</dc:title>
<dc:language>${escapeXML(language)}</dc:language>
${list(metadata.author).map(author => `<dc:creator>${escapeXML(author)}</dc:creator>`).join('\n')}
<meta property="dcterms:modified">2000-01-01T00:00:00Z</meta>
${fixedLayout ? '<meta property="rendition:layout">pre-paginated</meta>' : ''}
</metadata><manifest>
${manifest.join('\n')}
</manifest><spine${direction}>
${spine.join('\n')}
</spine></package>`
}

const navigation = async (book, targets) => {
    const entries = async items => {
        let html = ''
        for (const item of items ?? []) {
            const label = escapeXML(plain(item.label).trim() || 'Untitled')
            const address = item.href ? await targets.address(item.href) : null
            const children = item.subitems?.length ? await entries(item.subitems) : ''
            if (!address && !children) continue
            const link = address ? `<a href="${escapeXML(address)}">${label}</a>` : `<span>${label}</span>`
            html += `<li>${link}${children ? `<ol>${children}</ol>` : ''}</li>`
        }
        return html
    }
    let toc = await entries(book.toc)
    if (!toc) toc = `<li><a href="${sectionName(0, XHTML)}">${escapeXML(plain(book.metadata?.title) || 'Start')}</a></li>`
    return `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><ol>${toc}</ol></nav></body></html>`
}

// MARK: ZIP

const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1
    return c >>> 0
})

const crc32 = bytes => {
    let crc = 0xFFFFFFFF
    for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xFF] ^ (crc >>> 8)
    return (crc ^ 0xFFFFFFFF) >>> 0
}

/** A ZIP of `files`, stored without compression: it only lives until the reader closes. */
const zip = files => {
    const encoder = new TextEncoder()
    const parts = []
    const central = []
    let offset = 0
    for (const file of files) {
        const name = encoder.encode(file.name)
        const data = typeof file.data === 'string' ? encoder.encode(file.data) : file.data
        const crc = crc32(data)
        const local = new DataView(new ArrayBuffer(30))
        local.setUint32(0, 0x04034b50, true)
        local.setUint16(4, 20, true)
        local.setUint16(6, 0x0800, true) // UTF-8 names
        local.setUint32(14, crc, true)
        local.setUint32(18, data.length, true)
        local.setUint32(22, data.length, true)
        local.setUint16(26, name.length, true)
        parts.push(new Uint8Array(local.buffer), name, data)

        const entry = new DataView(new ArrayBuffer(46))
        entry.setUint32(0, 0x02014b50, true)
        entry.setUint16(4, 20, true)
        entry.setUint16(6, 20, true)
        entry.setUint16(8, 0x0800, true)
        entry.setUint32(16, crc, true)
        entry.setUint32(20, data.length, true)
        entry.setUint32(24, data.length, true)
        entry.setUint16(28, name.length, true)
        entry.setUint32(42, offset, true)
        central.push(new Uint8Array(entry.buffer), name)
        offset += 30 + name.length + data.length
    }
    const centralSize = central.reduce((size, part) => size + part.length, 0)
    const end = new DataView(new ArrayBuffer(22))
    end.setUint32(0, 0x06054b50, true)
    end.setUint16(8, files.length, true)
    end.setUint16(10, files.length, true)
    end.setUint32(12, centralSize, true)
    end.setUint32(16, offset, true)
    parts.push(...central, new Uint8Array(end.buffer))

    const result = new Uint8Array(offset + centralSize + 22)
    let position = 0
    for (const part of parts) {
        result.set(part, position)
        position += part.length
    }
    return result
}
