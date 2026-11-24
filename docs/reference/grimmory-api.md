# Grimmory API: what Dogear relies on

Endpoint shapes and server behaviour Dogear depends on, verified against Grimmory v3.5.0 source and a live v3.5.0 Server (non-admin account, Nov 2026).

Source: Grimmory v3.5.0 (`git clone --branch v3.5.0 https://github.com/grimmory-tools/grimmory`). Java paths are relative to `backend/src/main/java/org/booklore/`, frontend paths to `frontend/src/app/`. "Live" means observed on the running Server. Fixtures named below are in `Core/Tests/DogearCoreTests/Fixtures/`; anything marked "source only" was never seen live (the test Server had no PDF Book and no Book with several Book files).

## Gotchas

1. **The progress read doesn't mirror the write.** `PUT …/progress` takes `fileProgress`; `GET …/progress` returns the older per-format objects (`epubProgress`, `pdfProgress`, `audiobookProgress`) with no `bookFileId` and no `contentSourceProgressPercent`. See Shared position.
2. **`thumbnailUrl` in app DTOs is broken**: `/api/books/{id}/cover` returns the web app's HTML with 200. Build cover URLs from `/api/v1/media/...` (see Covers).
3. **`GET /api/v1/app/libraries` returns 500 for non-admins** (live, repeatable). Use `GET /api/v1/libraries`.
4. **Unknown `/api/...` paths return 200 `text/html`** (the web app's fallback). Status alone proves nothing; check the body is the expected JSON. `GET /api/v1/healthcheck` is public and Grimmory-shaped, so it's the pre-login probe.
5. **Two 401/404 body shapes** (API errors vs Spring Security). Branch on status, not body.
6. **A new refresh token is usable after ~60 s, not 120 s**: `nbf = iat + 120 s`, but Nimbus allows 60 s clock skew. Live: refresh 15 s after login → 401, at ~111 s → OK. A too-early refresh is indistinguishable from a revoked one (both 401 `Invalid credentials`) and **counts toward the rate limit**.
7. **The EPUB entry endpoint has no Range support and no `mimetype` entry** (404). See `readium.md`.
8. `canDownload` changed for the live test account between spike and implementation. Gating tests use fixtures, never the live account.

## Conventions

- Base path `/api/v1`, JSON. DTO timestamps are ISO-8601 UTC with `Z`; `ErrorResponse.timestamp` is a zone-less server-local `LocalDateTime` (don't parse it).
- Most DTOs are `@JsonInclude(NON_NULL)`: absent ≠ null. Decode everything optional except ids.
- Lombok primitive `boolean isX` fields serialize **without** `is`: `AppUserInfo.isAdmin` → `"admin"`, `AppBookFile.isBook/isPrimary` → `"book"`/`"primary"`. Boxed `Boolean` keeps it (`isDefaultPassword`, `isPhysical`).
- Auth: `Authorization: Bearer <access JWT>`. `?token=<access JWT>` also works on (`QueryParameterJwtFilter`, chains `@Order 4..8` in `config/security/SecurityConfig.java`): `/api/v1/media/**`, `/api/v1/epub/*/file/**`, `/api/v1/audiobooks/*/stream/**`, `/api/v1/audiobooks/*/track/*/stream/**`, `/api/v1/audiobooks/*/cover`, `/api/v1/books/*/download`, `/download-all`, `/books/*/files/*/download`, `/api/v1/custom-fonts/*/file`. **Not** `/api/v1/books/*/content` (live 401).
- Public: `/auth/login`, `/auth/refresh`, `/public-settings`, `/healthcheck`. `/version` **requires** auth.
- Paging (`AppPageResponse`): `{content, page, size, totalElements, totalPages, hasNext, hasPrevious}`; `page` 0-based; `size` max and default 50 (`AppBookService.MAX_PAGE_SIZE`).

## Errors

| Shape | When | Fixtures |
|---|---|---|
| `ErrorResponse {status, message, timestamp, details?}` (`exception/ErrorResponse.java`, `GlobalExceptionHandler.java`) | Thrown `ApiError`, `@PreAuthorize` denial (403 `"Access denied."`), validation (400 `"Validation error"` + `details`) | `error-403.json`, `error-404-book.json`, `error-404-track.json`, `login-wrong-password.json`, `refresh-rejected.json`, `rate-limited.json` |
| Spring Security `{timestamp, status, error, path}` | Missing/invalid/expired token (`AuthenticationCheckFilter` → `sendError(401)`), unmapped resource in a secured chain (404) | `error-401-unauthenticated.json`, `error-404-epub-file.json` |

- Missing, malformed, expired and wrong-signature access tokens all give the same Spring 401. There is no "expired" signal: any 401 on a non-auth endpoint means refresh once and retry.
- `ApiError` values that matter (`exception/ApiError.java`): `INVALID_CREDENTIALS` 401, `RATE_LIMITED` 429, `BOOK_NOT_FOUND` 404, `FORBIDDEN` 403 (`"Access denied to this book"`), `PERMISSION_DENIED` 403, `FILE_NOT_FOUND` 404, `FAILED_TO_DOWNLOAD_FILE` 500, `OIDC_ONLY_MODE` (password login blocked for non-admins).
- Dogear's mapping lives in `Core/Sources/DogearCore/Account.swift` (`check`, `performUnobserved`): 403/404 have their own errors, 5xx and 429 are retryable, and "server changed" is reserved for HTML answers, undecodable bodies and unexpected statuses.

## Auth

### `POST /api/v1/auth/login`
- Body `{username, password}` (both `@NotBlank`). 200 `{accessToken, refreshToken, expires, isDefaultPassword}`; `expires` is the **access-token lifetime in seconds (7200)**, not a timestamp. 401 for unknown user or wrong password alike. Flow: `config/security/service/AuthenticationService.loginUser`.
- `isDefaultPassword` is advisory: the **server doesn't block** default-password users (the web UI forces the change). Dogear enforces its own "change it in Grimmory first" message.
- JWTs (`config/security/JwtUtils.java`): HS256, `iss: "booklore"`, claims `sub`, `userId`, `isDefaultPassword`, `iat`, `exp`, `jti`. Access 2 h, refresh 30 d, refresh `nbf = iat + 120 s`.

### `POST /api/v1/auth/refresh`
- Body `{refreshToken}`. 200 `{accessToken, refreshToken, expires}` (no `isDefaultPassword`).
- **Rotation**: the old refresh token is revoked on success; reusing it → 401. Same 401 for not-found, expired, revoked and not-yet-valid. Hence single-flight refresh and never two within ~2 min.

### Rate limit (`config/security/service/AuthRateLimitService.java`)
- Counts **failed** attempts only; 5 failures ⇒ 429 until 15 min after the **first** failure (Caffeine `expireAfterWrite`; increments don't re-write). Success resets.
- Login is keyed by IP **and** normalized username; refresh by IP (`refresh:<ip>`). Behind a reverse proxy every device may share one IP.

### Other
- `GET /api/v1/public-settings`: `{oidcEnabled, remoteAuthEnabled, oidcProviderDetails, oidcForceOnlyMode}`.
- `GET /api/v1/healthcheck` (`controller/HealthcheckController.java`): `{"data":{"status":"UP",…,"version":"v3.5.0"},"message":"Pong","status":200,…}` (`healthcheck.json`).
- `GET /api/v1/version`: `{"current":…,"latest":…}`; `latest` comes from GitHub and may be null offline (`version.json`).

## User / permissions

- `GET /api/v1/app/users/me` → `AppUserInfo {canUpload, canDownload, canAccessBookdrop, maxFileUploadSizeMb, admin}` (`app-users-me.json`). Admins can always download (`@securityUtil.canDownload() or @securityUtil.isAdmin()`), so gate on `canDownload || admin`.
- `GET /api/v1/users/me` → full user with `permissions`, `assignedLibraries[]`, web reader `userSettings`.

## Books (`app/controller/AppBookController.java`, `app/service/AppBookService.java`)

### `GET /api/v1/app/books`
- Query (`app/dto/BookListRequest.java`): `page`, `size`, `sort` (`addedOn` default; `title`, `seriesName`, `lastReadTime`, `readStatus`, …), `dir`, `libraryId`, `shelfId`, `magicShelfId`, `search`, repeated `fileType=`, `status`, `authors`, `filterMode` (`or`/`and`/`not`).
- `fileType` matches **any** book-format file of the Book, not just the primary. Values `PDF, EPUB, CBX, FB2, MOBI, AZW3, AUDIOBOOK, PHYSICAL`; unknown → 400.
- `AppBookSummary` knows only the primary file (`primaryFileId`, `primaryFileType`, `primaryFileName`); the format list needs the detail endpoint. Also `coverUpdatedOn`, `audiobookCoverUpdatedOn`, `lastReadTime`, `readProgress`.
- `readProgress` is the per-Book percent with KOReader/Kobo taking precedence (`AppBookMapper.mapReadProgress`): never use it as a Position.

### `GET /api/v1/app/books/search?q=`
- Blank `q` → 400. Case-insensitive LIKE on title, series, authors; sorted by `addedOn` desc.

### `GET /api/v1/app/books/continue-reading?limit=` / `continue-listening?limit=`
- `limit` default 10, max 50. Plain arrays, ordered by per-Book `lastReadTime` desc, `readStatus ∈ {READING, RE_READING}` (`UserBookProgressRepository.findTopContinue*BookIds`). Reading = has a non-audiobook book-format file; Listening = has an audiobook file; a Book with both is in both (`continue-reading.json`, `continue-listening-empty.json`).
- `READING` is set when a save's percent > 0.1, `READ` at ≥ 99.5 (`ReadingProgressService.calculateReadStatus`), so a 0 % Position doesn't appear.

### `GET /api/v1/app/books/{bookId}`
- `AppBookDetail`: summary fields + metadata, `fileTypes[]`, `files[AppBookFile]`, and the same per-format progress objects as the progress read (`book-detail-*.json`).
- `AppBookFile {id, bookId, fileName, book, folderBased, bookType, archiveType, fileSizeKb, extension, addedOn, primary}`. `book:false` = supplementary file, ignore. `extension` is absent for folder audiobooks.
- Unsupported formats: `bookType == CBX`, or an `AUDIOBOOK` that is Opus (`extension == "opus"`; for folder books check track `fileName`s in the audiobook info). `MOBI`, `AZW3` (which also covers `.azw`) and `FB2` are converted to EPUB on the device (ADR 0005).
- 404 `BOOK_NOT_FOUND`; 403 `FORBIDDEN` when outside the account's libraries.

### Web Book DTO (`GET /api/v1/books/{id}`)
- Different shape (`model/dto/Book.java`); its `epubProgress` is the only read that exposes `contentSourceProgressPercent` and `ttsPositionCfi` (from the most recent *file* row, `ReadingProgressService.enrichBookWithProgress`). Dogear doesn't use it.

## Shared position

### `PUT /api/v1/app/books/{bookId}/progress`
- Send **only** `fileProgress` (`model/dto/request/BookFileProgress.java`): `{bookFileId, positionData, positionHref, progressPercent, ttsPositionCfi, contentSourceProgressPercent}`; optional sibling `dateFinished`. 200, empty body. The top-level `epubProgress`/`pdfProgress`/`audiobookProgress` are deprecated (the legacy audiobook path saves only the percent).
- Server flow (`service/progress/ReadingProgressService.updateReadProgress`): stamps server `now` on the per-file row and the per-Book `lastReadTime`, copies EPUB/PDF data into per-Book legacy columns, recomputes `readStatus`, fires KOReader and Hardcover sync. Client time is ignored (why ADR 0002 exists).
- `bookFileId` isn't checked against `bookId`; always send a matching pair.
- The per-Book percent column is chosen by the **primary** file's type, so on a multi-file Book an audiobook save overwrites the ebook percent the web UI shows. Harmless for Dogear's Positions.
- PDF `positionData` must be an integer string, or `Integer.parseInt` throws → 400.
- What each format carries (Dogear's encoding: `Core/Sources/DogearCore/SharedPositions.swift`):
  - EPUB: point CFI, resource href without fragment, whole-book % and in-resource %.
  - PDF: 1-based page; % = page ÷ page count (web: `pdf-reader.component.ts` ~L1208).
  - Audiobook: ms within the Track (single file: ms in the file) and Track index as `positionHref`; % rounded to 0.1. The web player (`features/readers/audiobook-player/audiobook-player.component.ts` `saveProgress` ~L830) sends `positionHref` **only for folder books** and reads `trackIndex ?? 0`, so a missing `trackIndex` means 0. It saves every 5 s while playing.

### `GET /api/v1/app/books/{bookId}/progress`
- `{readProgress, readStatus, lastReadTime, epubProgress?, pdfProgress?, cbxProgress?, audiobookProgress?, koreaderProgress?}`; `{}` when nothing is stored (`app-progress-empty.json`). Mapper: `app/mapper/AppBookMapper.toProgressResponse`.
  - `epubProgress {cfi, href, percentage, updatedAt}` and `pdfProgress {page, percentage, updatedAt}`: per-**Book** columns; `updatedAt` = per-Book `lastReadTime`.
  - `audiobookProgress {positionMs, trackIndex, percentage, updatedAt}`: the most recent audiobook **file** row (`UserBookFileProgressRepository.findMostRecentAudiobookProgressByUserIdAndBookId`); `updatedAt` is that file's time.
  - `lastReadTime` moves on **any** save for any file of the Book.
  - `epubProgress` is left out whenever the per-Book CFI column is null (`mapEpubProgress` checks `getEpubProgress()`), and an EPUB push with no `positionData` nulls it. So an EPUB push without a CFI erases the Shared position for every reader; Dogear keeps such Positions on the device (`Positions.record`).
- The web reader's `href` carries a `#fragment` (TOC/page-list href); strip it (`app-progress-epub.json`).
- Stale entry check (ADR 0002) compares against the matching format's `updatedAt`. For EPUB/PDF that is still the per-Book time, which also moves when another file of the Book is read: the best v3.5.0 offers. A Book with two EPUBs or two audiobooks can't be told apart; out of scope.

## Libraries and shelves

- `GET /api/v1/libraries` (`controller/LibraryController.java`): `[{id, name, icon, …, paths[], allowedFormats[]}]`, assigned libraries only for non-admins, no `bookCount` (`libraries-web.json`). Books: `app/books?libraryId=`.
- `GET /api/v1/app/shelves` → `[{id, name, icon, bookCount, publicShelf}]` (`app-shelves.json`). Books: `app/books?shelfId=`.
- `GET /api/v1/app/shelves/magic` → magic shelves; books via `…/magic/{id}/books` or `?magicShelfId=`.
- `GET /api/v1/app/filter-options` → `{name, count}` lists per facet (`fileTypes`, `libraries`, `shelves`, `authors`, `languages`).

## Covers (`controller/BookMediaController.java`, `?token=` accepted)

| Path | |
|---|---|
| `/api/v1/media/book/{id}/thumbnail`, `/cover` | ebook cover, thumb and full |
| `/api/v1/media/book/{id}/audiobook-thumbnail`, `/audiobook-cover` | audiobook cover |
| `/api/v1/audiobooks/{id}/cover?bookType=` | cover embedded in the audio file |

- An audiobook-only Book has **no** ebook thumbnail (404). Pick by `coverUpdatedOn` / `audiobookCoverUpdatedOn` presence; the web app uses the timestamp as a cache-buster (`shared/service/url-helper.service.ts` L27/L55), Dogear as the cache key.
- No token → 401.

## EPUB (`controller/EpubReaderController.java`): no `canDownload` check

### `GET /api/v1/epub/{bookId}/info?bookType=`
- `{containerPath, rootPath, spine[{idref, href, mediaType, linear}], manifest[{id, href, mediaType, properties, size}], toc, metadata, coverPath}`; hrefs are zip-root-relative. `spine` **includes** `linear:false` items but not the itemrefs' own `id` attributes (CFIs need those, so Dogear parses the OPF instead). `manifest[].size` = uncompressed bytes.
- A non-EPUB Book → 500.

### `GET /api/v1/epub/{bookId}/file/{*filePath}?bookType=`
- One entry from inside the zip; header or `?token=` auth. Headers: per-entry `Content-Type`, `Content-Length`, `Cache-Control: private, max-age=3600`, `Content-Security-Policy: script-src 'none'` (irrelevant through Readium's scheme handler; matters if these URLs ever load straight into a WKWebView).
- **No Range** (`Range` → 200 full body, no `Accept-Ranges`). HEAD works. `META-INF/container.xml` 200, **`mimetype` 404**, missing entry → Spring 404.

## MOBI, AZW3, FB2: no `canDownload` check (source only)

- `GET /api/v1/books/{bookId}/content?bookType=MOBI|AZW3|FB2`, as the web reader loads them whole (`frontend/src/app/features/book/service/book-file.service.ts`). No file of that type → 404 `FILE_NOT_FOUND`. Implementation: `Core/Sources/DogearCore/ServerConvertible.swift`.
- No conversion endpoint exists. Positions are saved and read back as `epubProgress`, the same fields as an EPUB's (`ReadingProgressService`, `case EPUB, FB2, MOBI, AZW3`), and the progress read, like for EPUBs, keeps one per Book.

## PDF: no `canDownload` check (source only)

- `GET /api/v1/books/{bookId}/content?bookType=PDF` (`BookController.getBookContent`): **header auth only**; Range-capable (live on an EPUB: 206, `Accept-Ranges: bytes`), `Cache-Control: no-cache, private`. Serves any format.
- `GET /api/v1/pdf/{bookId}/info?bookType=` → `{pageCount, outline[]}`; `/pdf/{bookId}/pages` → `[Int]` (`controller/PdfReaderController.java`).

## Downloads

| Endpoint | `canDownload` | Notes |
|---|---|---|
| `GET /api/v1/books/{id}/download` | **required** (403 `"Access denied."`) | Primary file only. **Ignores Range** ⇒ no resume. Folder audiobook ⇒ server-built ZIP (`BookDownloadService.downloadFolderAsZip`). |
| `GET /api/v1/books/{id}/download-all` | required | ZIP of all files. |
| `GET /api/v1/books/{id}/files/{fileId}/download` | **not checked** (`AdditionalFileController`, only `@CheckBookAccess`) | Non-primary files only; primary → 400. |

- The reader and stream endpoints don't check `canDownload` either. Dogear gates every Download on `canDownload || admin` itself, and fetches folder audiobooks Track by Track to avoid the ZIP (`Core/Sources/DogearCore/Downloads.swift`).

## Audiobooks (`controller/AudiobookReaderController.java`)

### `GET /api/v1/audiobooks/{bookId}/info?bookType=`
- `{bookId, bookFileId, title, author, narrator, durationMs, bitrate, codec, sampleRate, channels, totalSizeBytes, folderBased, chapters?, tracks?}`. `bookFileId` is what the progress PUT needs.
- Single file (M4B): `chapters[{index (0-based), title, startTimeMs, endTimeMs, durationMs}]`, no `tracks` (`audiobook-info-single.json`).
- Folder: `tracks[{index, fileName, title, durationMs, fileSizeBytes, cumulativeStartMs}]`, no chapters (`audiobook-info-folder.json`).

### Streams (header or `?token=`)
- Whole file `/api/v1/audiobooks/{id}/stream[?bookType=][&trackIndex=]`; per Track `/api/v1/audiobooks/{id}/track/{i}/stream` (same bytes as `stream?trackIndex=`).
- Range works: 206 with `Content-Range`, 416 `bytes */<total>` when unsatisfiable. `Content-Type` `audio/mp4` (m4b) / `audio/mpeg` (mp3). Bad token → Spring 401 JSON. Track out of range → 404 `"File not found: Track index out of range: N"`.
- The web player's `ngsw-bypass=true` is for its service worker only.
