# Player controls: device checklist

AVFoundation, the lock screen and AirPlay aren't covered by automated tests (spec #1), so check these on an iPhone before a release. Use a single-file audiobook with Chapters and a folder audiobook.

## Speed

- [ ] Each preset (0.75× to 3×) changes speed while playing and while paused (applies on play).
- [ ] Speech stays at normal pitch at 2× and above.
- [ ] The speed is kept after closing and reopening the player, and across app launches.
- [ ] Leave it playing past an access token refresh (or sign the Server out of the token): playback continues at the chosen speed.
- [ ] Lock screen and Control Center show time advancing at the chosen speed.

## Sleep timer

- [ ] 5 minutes: playback pauses after 5 minutes of listening; pausing midway extends it by the paused time.
- [ ] End of Chapter: pauses at the start of the next Chapter, without playing into it.
- [ ] End of Chapter, then skip or pick another Chapter: pauses at the end of the new Chapter.
- [ ] Folder audiobook, End of Chapter: pauses when the current Track ends.
- [ ] Turn Off cancels it. The timer keeps running with the phone locked.

## Skip

- [ ] Back 15 s and forward 30 s in the app, including across a Chapter and (folder) a Track boundary.
- [ ] The lock screen and Control Center show skip buttons (not next/previous) and they skip 15 s / 30 s (or the times chosen in Settings).
- [ ] Change the skip times in Settings while an audiobook is loaded: the keys' labels, the jumps and the lock-screen buttons follow straight away.
- [ ] The lock-screen scrubber seeks.
- [ ] Headphone/AirPods play-pause works.

## Now Playing

- [ ] Lock screen shows the audiobook cover, Book title, author and the current Chapter, updating as Chapters change.

## AirPlay

- [ ] The route button lists AirPlay speakers and Bluetooth; playing to an AirPlay speaker keeps working with the phone locked and after a token refresh.

## Interruptions

- [ ] An incoming call pauses playback; ending the call resumes it.
- [ ] Siri pauses playback and it resumes afterwards.
- [ ] Starting music in another app stops the audiobook, and it doesn't resume by itself.
- [ ] Unplugging wired headphones or disconnecting AirPods pauses; reconnecting doesn't start playback by itself.
- [ ] After each pause above, the Position saved matches where playback stopped.
