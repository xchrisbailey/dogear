# Coding standards

Judgement calls for review. Mechanical rules are enforced by `scripts/check-*.sh` (CI and the pre-commit hook) and aren't repeated here. Vocabulary comes from `GLOSSARY.md`; decisions from `docs/adr/`.

## Server responses

- **"Server changed" means an unexpected shape only**: HTML where JSON was expected, or JSON that won't decode. Statuses have their own meanings: 401 refreshes, 403 is a permission (Downloads off, Book not visible), 404 is a gone Book or Book file, 5xx and no connection are offline. A status mapped to "server changed" shows "update Dogear" for something an update won't fix.
- **An error that can never succeed drops the work; a transient one keeps it.** An Outbox entry for a gone Book file is dropped so later entries still flush; an offline failure stops the flush and keeps everything.
- **One bad item never fails a batch.** A library refresh keeps the rest when one Book's detail fails.

## Positions

- **Only reader-initiated moves record a Position**: page turns, scrolling, table-of-contents jumps, playback, and resolving the opening Position. Relocations caused by layout (controls toggling, rotation, settings, spreads) record nothing, because a later record wins newest-wins over newer reading elsewhere (ADR 0002).
- **Readers and the player catch up to a newer Shared position** when they return to the foreground.
- **Position vocabulary in code**: names for where the reader is use Position terms (`throughBook`, `throughChapter`). Types that decode or encode Grimmory's wire format keep Grimmory's field names (`fileProgress`, `epubProgress`), and Download transfer progress is its own concept.

## Storage

- **Only Downloads persist Book content for offline use.** Anything else opened from the Server (a PDF that isn't downloaded) lives in a temporary file removed on close, so `canDownload` stays meaningful.

## Tests

- **Seam 1 tests drive Core through the fake Grimmory Server** and assert on what's stored, shown or sent. A rule that lives only in the App target (and so has no seam 1 test) is a finding: move the decision into Core and leave the App the platform mechanics.
