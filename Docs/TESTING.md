# Testing strategy

* **Unit tests** (`swift run digby-dl-tests`, no XCTest needed): URL parsing and site identity, catalogue building,
  resolution tiers (incl. portrait/odd sizes), codec and container compatibility, language selection (original vs dub,
  fallback), subtitle selection, plan deviations/unsatisfiable cases, file naming and sanitising, collision handling,
  error classification, retry policy, queue state machine, SQLite migrations, redaction, manifest/version comparison.
* **Fixtures**: recorded `yt-dlp -J` JSON for representative sources (YouTube multi-codec + multi-audio + HDR, Vimeo,
  a playlist, an audio-only site, a muxed-only site) and recorded error outputs. Stored under `Tests/Fixtures/`, scrubbed
  of anything personal. Selection logic is tested only against fixtures, so results are deterministic.
* **Dependency tests**: local fake release server (files + checksums + good/bad signatures) → install, reject tampered
  file, update, rollback, interrupted install leaves previous version active.
* **Integration** (`digby-dl` CLI, rate-limited, public freely licensed media only — never private, paid or DRM content):
  analyse → download → verify for each type/container combination; cancellation; pause/resume.
* **UI**: offscreen renders of every state in light and dark; VoiceOver labels audited from the accessibility tree.
* **Robustness**: kill the app mid-download and relaunch → queue intact, no orphan processes, no partial files presented as done.

## Current state (Phase 2)
* `swift run --scratch-path "$TMPDIR/digby-dl-build" digby-dl-tests` → 159 checks (families, tiers, catalogue, selection
  defaults, never-silently-compromise cases, languages, audio-only, video-only, muxed-only sites, subtitles, determinism,
  plain-English house rules). Also run by `Scripts/build_app.sh`.
* UI: `DIGBY_DL_RENDER=<dir> "build/Digby Video Downloader.app/Contents/MacOS/Digby Video Downloader"` writes every
  state in light and dark plus full-length pages (`*-full.png`); `DIGBY_DL_STATES=ready,queue` limits the set.
  Selected renders are kept in `Docs/Screens/`.

## Phase 3 additions
* Unit tests now 189 checks, adding: OpenPGP verification on yt-dlp's real signed checksums (genuine passes, tampered data and
  corrupted signature fail), decoding real scrubbed engine output (`Tests/Fixtures/*.json`: Internet Archive, Wikimedia
  Commons), error classification from real messages, redaction, file naming and collision handling.
* End-to-end with `digby-dl` (isolated `DIGBY_DL_HOME`, `--to` a scratch folder), public freely licensed media only
  (Blender's *Big Buck Bunny*, CC-BY): engine install from scratch; WebM + embedded subtitles; MP4 copy; MP3 conversion;
  separate .srt files; duplicate name; cancel mid-download (no orphan processes, no partial files).
* App end-to-end: `DIGBY_DL_HOME=… DIGBY_DL_DOWNLOADS=… DIGBY_DL_E2E=<link> DIGBY_DL_E2E_RES=360 DIGBY_DL_E2E_OUT=<dir>`
  runs the bundled app through analyse → download → verify and snapshots each stage.
* Not yet testable from this Mac: YouTube (bot check) and Vimeo (403) — see IMPLEMENTATION_STATUS.

## Phase 4 additions
* 209 unit checks: real YouTube answer (stream choice avoids HLS-combined, DRC and IAMF tracks), cookie-jar trimming and
  permissions, YouTube link recognition (incl. look-alike domains), SQLite history (order, search with literal %/_,
  filters, remembered choices, record removal keeps the file, survives reopening).
* YouTube end to end (CLI and app) through Astrill with `digby-dl signin youtube brave`.
* Pause/resume: `digby-dl download … --work-id ID --pause-at 8`, then the same command without `--pause-at`.

## Manual release checklist (1.1.0)
Things only a person at this Mac can confirm. Use the built app (`build/Digby Video Downloader.app`, or install from the
DMG to also check the first-launch step). Tick each one; anything that fails goes into IMPLEMENTATION_STATUS.

**Install and first run**
- [ ] DMG opens; drag to Applications; first launch needs "Open Anyway" (macOS 15+) exactly as the README says.
- [ ] On a Mac or user account that never ran Digby: the engines install by themselves, then a link works.

**Everyday downloads**
- [ ] YouTube link → Best shows 1080p (on M1/M2) with the "choose 4K" note; download → plays in QuickTime.
- [ ] Choose 4K on the same link → AV1/VP9 offered with the "Convert to MP4" option; both ways finish and are checked.
- [ ] Audio only → MP3 and M4A; a playlist (tick a few); subtitles inside the video and as separate files.
- [ ] Part of the video (quick and exact cut); subtitles on the picture; Translate into… (macOS 15+).
- [ ] Open a link you already downloaded → "You already downloaded this…" with Show in Finder.
- [ ] Pause, Resume, Cancel, Try Again on a failed one; reorder; speed limit; Overnight (set a window a few minutes ahead).

**When things go wrong**
- [ ] Force-quit Digby (⌥⌘Esc) mid-download → reopen → Continue picks up where it stopped.
- [ ] Quit normally mid-download → the dialog says what's kept → reopen → Continue.
- [ ] A missing page (e.g. a Commons file that doesn't exist) → "This page doesn't exist".
- [ ] A live stream → "This is live right now".
- [ ] Facebook post → Find the Video: page loads (or the "keeps sending the page back and forth" card → Clear and Reload works).
- [ ] Rumble or Vimeo → Find the Video → pass the check → caught → download.
- [ ] A site that needs Play the Page Out of Sight → asked once ("Allow for …") → allowed → later links just work;
      Settings → Privacy lists the site; Don't Allow / Ask Again work.
- [ ] Closing the Find the Video window stops all sound.

**Mac integration**
- [ ] ⌃⌥⌘D downloads the copied link; menu-bar icon; notifications (after turning them on); Dock count.
- [ ] Browser button (Chrome/Brave) and the bookmark in Safari open the page in Digby.
- [ ] Quick Look (Space) in Downloaded; drag a finished file to Finder; Compress with Digby.
- [ ] Watching: add a channel, Check Now, a new video downloads with the saved choices.
- [ ] Projects: new project, paste into it, files land in its folder.
- [ ] Sign-in: your browser's sign-in for YouTube; the sign-in window inside Digby (Google).
- [ ] Light and dark mode; the narrowest window size; VoiceOver reads the choice rows and buttons sensibly.
