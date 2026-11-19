# EPUB Positions: read and write CFIs with foliate's epubcfi.js

Supersedes ADR 0003. Grimmory's web reader (foliate-js) restores EPUB Positions from a CFI first, and its href-plus-in-chapter fallback only lands at the chapter start (tested live on v3.5.0). A Nov 19 spike showed Dogear can do CFIs both ways inside Readium 3.11.1 by injecting foliate's MIT `epubcfi.js` as a user script and calling it through `evaluateJavaScript`: resolving web-reader CFIs landed on the right text, and the web reader landed on the right spread from a Dogear-generated CFI near a chapter's end. Readium only adds attributes to `<html>`/`<body>` and puts its CSS in `<head>`, so CFI step indices match the raw XHTML.

Dogear writes the start of the visible range as a point CFI (`/6/N[idref]!` joined to `CFI.fromRange`), plus the resource href, `contentSourceProgressPercent` and overall progress, so the web reader has a fallback if the CFI ever fails.

## Considered Options

- **Never write CFIs (ADR 0003)**: safe if a Dogear CFI were ever wrong, but costs everything past the first page of a chapter when resuming on the web.
- **Percent/href only**: same loss, and worse when reading in Dogear.

## Consequences

- A CFI Dogear writes that the web reader can't resolve makes the web reader fail silently, with no fallback. Inject epubcfi.js via `WKUserScript`, never as a `<script>` element, so it doesn't change the DOM's step indices. Compare CFIs by their collapsed start, not the full range string, since range ends depend on the viewport.
- `evaluateJavaScript` fails until the navigator has fired its first `locationDidChange`. Resolving takes about 2 s cold and 0.8 s warm.
- An upstream fix to the web reader's in-chapter restore is still worth sending, as a fallback for everyone.
