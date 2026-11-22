# MOBI, AZW3 and FB2: convert to EPUB on the device with foliate-js

Grimmory serves MOBI, AZW3 (KF8) and FB2 Book files as they are, with no conversion (checked on its main branch, Nov 2026; Kobo sync only turns EPUBs into KEPUBs). Its web reader opens them in the browser with foliate-js, which splits each file into HTML sections, and saves their Positions exactly like an EPUB's (`epubProgress`: a CFI whose spine step is `/6/((index + 1) × 2)` with no ID assertion, the section's href and a percentage; `ReadingProgressService`, `case EPUB, FB2, MOBI, AZW3`).

Dogear converts them to an EPUB on the device and opens that in its existing EPUB reader. A web view that's never shown runs foliate-js's own `mobi.js` and `fb2.js` (MIT, the revision Grimmory ships) through `App/Reader/Resources/ebook-to-epub.js`, which writes each section into the EPUB exactly as the web reader displays it, in the same order, as the package document's third element with ID-less itemrefs. The CFIs Dogear's bridge reads and writes (ADR 0004) then match the web reader's for the same text, so Positions sync both ways, and the page curl, reading settings, Contents, Downloads and Continue rows all work unchanged. Only attribute values change in a section (resource and link addresses), which CFIs don't count.

## Considered Options

- **A second reader built on foliate's own view and paginator in a WKWebView**: the same CFIs for free, but a whole second reader to keep in step with the EPUB one (page turns, settings, themes, folio, the bookshelf look).
- **A Swift MOBI/KF8 parser**: thousands of lines to match foliate's sectioning exactly, or CFIs wouldn't match.
- **Ask the reader to convert with Calibre and add the EPUB in Grimmory**: no code, but every such Book is a dead end until they do.

## Consequences

- Converting takes a second or two on opening, every time: a Download keeps the file as the Server sent it, and the EPUB is a temporary file removed on close, like a fetched PDF, so only Downloads keep Book content (CODING_STANDARDS).
- Readium only paginates the reading order, which leaves out `linear="no"` sections (an FB2's notes), as foliate's paginator does.
- DRM-locked files (PalmDOC encryption set) can't be opened and say so. foliate itself doesn't check.
- If KF8 markup isn't valid XHTML, foliate parses it as HTML from then on, so which sections are HTML depends on the order the web reader loaded them. Dogear loads them in order; a Book where that differs can have CFIs that don't resolve, and falls back to the href and percentage.
- Grimmory updating its vendored foliate-js could change sectioning; `mobi.js`, `fb2.js` and `epubcfi.js` should move to the same revision when it does. Checked in Chromium on Calibre-made fixtures: every section's DOM and every text node's CFI matched what foliate loads.
