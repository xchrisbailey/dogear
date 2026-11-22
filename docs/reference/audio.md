# Audio: AVFoundation behaviour with Grimmory streams

How AVPlayer behaves against Grimmory's audiobook streams, measured on iOS 27.2 (simulator) against a live Grimmory v3.5.0 Server, Nov 2026. Endpoint details: `grimmory-api.md` → Audiobooks.

Implementation: `App/Player/AudiobookPlayerModel.swift`; URLs and token handling in `Core/Sources/DogearCore/ServerAudiobook.swift`; queue and seek rules in `Core/Sources/DogearCore/AudiobookQueue.swift`.

## Token in the URL

- AVPlayer can't add headers portably, so the access token rides as `?token=` (`QueryParameterJwtFilter`). Every seek opens new range requests on the same URL and the query token worked for all of them (4 seeks, 0 stalls).
- **Never log stream URLs**: they carry the token.
- Each `AVPlayerItem` is stuck with the token it was built with, and access tokens live 2 h. Dogear rebuilds items and seeks back whenever the token changes, and once more after an item fails.
- **Still unverified**: what AVPlayer does when the token expires mid-item. Later range requests should 401, but whether that surfaces as item failure or as a stall wasn't observed.

## Single file (M4B)

- Measured on a ~900 MB, 16 h file: 3.1 s to `playing`, 13.7 MB pulled first because the `moov` atom is at the end. Expect that on every cold item, including token rebuilds.
- Zero-tolerance seeks: 33–717 ms.
- Chapter `index` is 0-based (index 20 may be titled "021").

## Folder audiobook (MP3 Tracks)

- 81-Track book: started in 257 ms; `AVQueuePlayer` **preloaded the next Track** and advanced with no audible gap. In-Track seek ~45 ms.
- `AVQueuePlayer` can't go backwards: going to an earlier Track means rebuilding the queue from that Track on.

## Failure is silent

- With a bad token the item failed, the **queue dropped it**, and the player sat in `.waitingToPlayAtSpecifiedRate` with `AVPlayerWaitingWithNoItemToPlayReason`: no error-log entry, no `failedToPlayToEndTime`. Only KVO on each item's `status` catches it.
- A server 401 surfaces as a generic `AVFoundationErrorDomain` error; the status isn't readable from the player. To classify, probe the URL from the core client (e.g. `Range: bytes=0-0`). Dogear instead tries a fresh token once before showing an error.

## Other behaviour worth knowing

- A seek fires the periodic time observer at the target immediately, so a save after scrubbing comes for free.
- `player.defaultRate` is what `play()` uses, including after an item rebuild, so speed is set there as well as on `rate`.
- `.longFormAudio` session policy routes AirPlay properly for audiobooks.
