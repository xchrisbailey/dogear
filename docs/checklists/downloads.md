# Downloads: device checklist

The background URLSession isn't covered by automated tests (spec #1); seam 1 covers `canDownload` gating, storage accounting and opening from the device. Check these on an iPhone against an HTTPS Server, with an EPUB, a PDF, a single-file audiobook and a folder audiobook.

## Downloading

- [ ] Long-press a Book: "Download" shows for each supported Book file; progress shows in the row while it downloads.
- [ ] Start a folder audiobook download, leave the app: it finishes in the background, and the row shows it downloaded on return.
- [ ] Start a large download, quit the app from the app switcher, relaunch: the download starts again.
- [ ] Turn on Airplane Mode mid-download: the Download shows as failed; "Retry Download" carries on without fetching finished Tracks again.
- [ ] Downloads survive a relaunch and an iOS storage-pressure purge (they live in Application Support).

## Opening from the device

- [ ] In Airplane Mode, a downloaded EPUB, PDF, single-file audiobook and folder audiobook each open and resume at their Position; Positions wait in the Outbox.
- [ ] A PDF that isn't downloaded doesn't open offline (nothing is kept after closing it).

## Storage and permission

- [ ] The Downloads screen shows size per Book and the total; swipe removes one; "Remove All Finished" leaves in-progress ones.
- [ ] With `canDownload` off for the account in Grimmory (and not an admin), relaunch: download options are hidden; existing Downloads still open and can be removed.
- [ ] Sign out with Downloads present: the warning mentions them, and they're gone afterwards.
