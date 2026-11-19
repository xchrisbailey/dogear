# Dogear

Native iPhone and iPad app for reading ebooks and listening to audiobooks from a self-hosted Grimmory server, with offline downloads and progress that stays in step with Grimmory's web reader.

## Library

**Server**:
The Grimmory instance Dogear is signed in to, reached by an address the user enters.
_Avoid_: Backend, instance, host

**Book**:
One title in the Grimmory library. A Book can hold several Book files, such as an EPUB and an audiobook of the same title, and appears once in Dogear's library.
_Avoid_: Title, item, entry

**Book file**:
One readable or listenable file belonging to a Book: an EPUB, a PDF, or an audiobook (single M4B or a folder of tracks).
_Avoid_: Format, edition, asset

**Track**:
One audio file within a folder audiobook.
_Avoid_: Part, segment

**Chapter**:
A named point inside an audiobook's audio (embedded in an M4B) or a section of an ebook.

**Download**:
A Book file stored on the device so it can be read or played without reaching the Server.
_Avoid_: Offline copy, cache

## Progress

**Position**:
Where the user is in one Book file. For an ebook, a spot in the text; for an audiobook, a Track and time within it. Shown as "progress" in the UI.
_Avoid_: Progress (in code and docs), locator, bookmark, spot

**Shared position**:
The Position Grimmory stores for its web reader and app clients, which Dogear reads and writes. KOReader and Kobo progress are separate and not Shared positions.
_Avoid_: Server progress, sync progress

**Outbox**:
Positions recorded on the device that have not yet been accepted by the Server.
_Avoid_: Queue, pending sync, backlog

**Stale entry**:
An Outbox entry recorded earlier than the Shared position the Server already holds; it is discarded rather than pushed.

## Integrations

**Hardcover**:
The external reading log where progress and reading status are recorded. Dogear never talks to it directly; the Server does.
