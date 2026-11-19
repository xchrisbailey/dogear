# Hardcover sync goes through Grimmory, not Dogear

Grimmory already pushes progress to Hardcover whenever a Shared position is saved, including from the app progress endpoint Dogear uses, so Dogear has no Hardcover client or token. This avoids logging the same progress twice and sidesteps Hardcover's guidance against users pasting personal tokens into apps (and its terms on commercial use), which would otherwise block an App Store release.

## Consequences

- Audiobook progress reaches Hardcover as pages (percentage × edition page count), never as seconds, and is skipped when the edition has no page count. Fix upstream in Grimmory by sending `progress_seconds`, not in Dogear.
- Hardcover matching and the Hardcover token live in Grimmory's per-user settings; Dogear can only show what the Server reports.
