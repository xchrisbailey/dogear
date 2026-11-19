---
status: superseded by ADR-0004
---

# EPUB Positions: read the web reader's CFIs, never write them

Grimmory's web reader (foliate-js) stores EPUB Positions as range CFIs and restores CFI first, then chapter href plus in-chapter progress, then overall percentage. Readium has no CFI support and won't add it. A CFI that's present but unresolvable makes the web reader silently fail to restore, with no fallback, so Dogear never writes one: it sends a null CFI, the resource href, in-chapter progress (`contentSourceProgressPercent`) and overall progress. When reading the Shared position, Dogear resolves the web reader's CFI in-page via JavaScript (foliate's MIT `epubcfi.js` through Readium's `evaluateJavaScript`) and falls back to the CFI's spine step plus overall percentage if that fails.

## Considered Options

- **Never use CFIs**: safe, but web → Dogear resumes only to the chapter, possibly pages off.
- **Read and write CFIs**: exact both ways, but a CFI skewed by Readium's DOM changes would silently break the web reader's resume.

## Consequences

- Dogear resuming from the web reader is exact. Web reader resuming from Dogear lands at the start of the chapter: tested live on Grimmory v3.5.0 (Nov 19), the web reader ignores `contentSourceProgressPercent` despite code meant to apply it, then saves its own chapter-start CFI over Dogear's Position. Fixing that in-chapter restore upstream would bring it to within about a page.
- Writing CFIs (option B) is the intended next step if the spike shows Dogear can generate CFIs identical to foliate's for the same spot.
- Upgrading to writing CFIs later only means turning on the write side once in-page CFI generation is proven against the web reader.
- The web reader's `positionHref` is a TOC href (may point to an earlier file or carry a fragment) and is treated as a hint only.
