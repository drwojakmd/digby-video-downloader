# Implementation status

_Last updated: 2026-11-15 — **1.1.0 ready for full testing (release fixes in Round 8 below; manual checklist in `TESTING.md`); 1.0.0: all seven phases complete.** Built, tested, packaged (DMG), committed
locally. Not yet published (needs your go-ahead: public GitHub repository, release, website)._

## Engine freshness and site success (2026-11-16)
| Area | State | Evidence |
|---|---|---|
| **Quick engine check** | Besides the daily full check, yt-dlp's newest release name is asked every 4 h on Stable (2 h on Nightly): one GitHub API request; the signed checksums are fetched only when there's something to install. A failed check retries after 15 min, then 30, 60 … up to the usual interval. Updates still install only when nothing is downloading. | 12 unit checks (`UpdateSchedule`, `CheckState`) |
| **Site changed → fix** | The newest build on your channel is fetched at once and the page re-read. On Stable, if that doesn't fix it, the failure card offers **Try the Nightly Engine** (explained, pros and cons): verified the same way, steps shown on the diagnosing card, waits for running downloads. A nightly fetched this way is kept until a Stable release of the same day or newer arrives; choosing a channel by hand clears that. (Before, Digby fell back to Nightly silently.) | 12 unit checks (`EngineEscalation`, `EngineChoice`, `EngineRecovery` with a faked server) |
| **Site success table** | Settings → Diagnostics: per site, tries, worked, rate, usual problem; engine version, last engine update, last checked. Kept in `site-stats.json` (site domain, worked or not, problem kind, yt-dlp version; no links or titles; newest 5,000, one year). **Copy Report** copies a summary (sites and counts); nothing is sent. **Clear…** resets it. | 13 unit checks; render `Docs/Screens/settings-diagnostics-light.png` |

## 1.1 improvements (2026-11-14, from your feedback)
| Area | State | Evidence |
|---|---|---|
| **Several links at once** | Every pasted link becomes a tab (a "draft") above the page: reading → ready → downloading → done/failed, each independent. The link field always accepts another link; × closes a tab (a running download carries on under Downloads). | Builds; tab tray rendered |
| **Details after a download** | The original as the site offered it (resolutions, formats, frame rates, HDR, languages, subtitles, chapters), what you chose (in plain words), and what was verified (file, size, checked streams). From the finished card, Downloads (ⓘ) and History (Details / double-click). Saved in History (database schema 2; 1.0 histories upgrade in place). | 6 unit checks incl. upgrading a 1.0 database |
| **Find the Video on the Page** | The page opens in Digby's own browser (private, remembers sign-ins and site checks; Settings → Privacy → Forget All). You play the video; Digby catches the player's playlist or file (ignoring the thousands of pieces), labels it ("Video stream, up to 1080p", "Video file · 300 MB"), suggests the best, then analyses it with the page's headers and cookies and shows the usual choices. Offered on failure cards, as a link under every preview, and ⇧⌘F. | Real test on Wikimedia Commons: caught 2 files, chose 1080p, downloaded 300 MB, verified. Second real test (Internet Archive) below. 9 unit checks on classification |
| **Sign-in for any site** | Any site (vimeo.com, rumble.com…) can use your browser's sign-in (read fresh, never stored) or a Digby sign-in window ("I'm Signed In"). Cookies only ever go to that site's own domains. Settings from 1.0 still load. | 5 unit checks |
| **Sites that hide what's in a file** | Files a site describes with no codec details (common on X, BitChute and smaller sites) are now treated as "unknown, to inspect", and HLS playlists are inspected too (with the site's headers), instead of being dropped or refused. | Unit checks; needs your failing links to confirm per site |
| **No AI attribution** | All commits in the Downloader and website repositories rewritten as "Digby" only. The public Compressor repository needs a force-push (waiting for your OK). | `git log` |

### Round 2 (your test links and feedback)
| Area | State |
|---|---|
| Tabs **or** list | Open links as tabs above the page, or as rows in the sidebar under New Download (switch next to the tabs; remembered). |
| Convert to MP4 / keep the site's file | Explicit choices when a file type can't hold the picture (VP9/AV1 into MP4/MOV) or this Mac can't play it (AV1 on M1/M2): "Convert to MP4 (plays everywhere, takes longer)" re-encodes the picture as H.264 (CRF 18), checked afterwards; "Keep the site's MP4 as it is" copies the site's own file. Shown as one-click buttons; size estimated from picture size (54.6 MB estimated vs 53.9 MB real). Never automatic. |
| Automatic fallbacks | When the engine can't read a page: engine update (Stable, then Nightly) → your browser's sign-in, if you allowed it for any site that refuses (read fresh, remembered per site when it works) → Digby-browser session, if you've used that site in "Find the Video" before → a hidden, off-screen page catch (plays the page muted, catches the player's stream; tries candidates until one has a picture). Only then the failure card. |
| Find the Video on the Page | Catches player addresses with no file extension by following them (Substack → Mux), addresses written into the page, and byte-range pieces; whole files rank above single-quality playlists. "Download from This Page" is always available: the engine reads the page with what you did in Digby's browser (signed in, passed a check). Facebook-style byte-range pieces now count as the files they belong to. |

| Your link | Result here (behind Astrill) |
|---|---|
| X (Brownstone) | Works: 1080p60 H.264 + AAC, copied. |
| X (your post) | Works automatically: engine refused, retried as you (Brave), downloaded and verified. |
| Facebook reel | Works: AV1 or VP9 offered by Facebook; "Convert to MP4" gave a verified 1080×1920 H.264 MP4 (80 s video, 59 s). |
| BitChute | Works: 480p (VP9 inside the site's MP4) — keep as is, MKV/WebM, or convert. |
| Substack post | Works automatically: engine can't read it; the hidden catch follows the player's own address to Mux's master playlist → 720p/480p/240p H.264 + AAC, MP4, copied (≈ 260 MB for 24 min). Streamed pieces now download four at a time. |
| Substack note | Same route as the post (see the latest test in the session notes). |
| Facebook reel in Find the Video | The player's pieces come from a background worker the catcher can't see, so the list stays empty — **Download from This Page** reads the page with your Digby-browser session instead (tested: 720p H.264 + AAC MP4, verified; generic "Video" titles replaced by the page title). After signing in once there, later Facebook links use that session automatically. |
| Rumble, Vimeo | Refused on this connection by Cloudflare/Turnstile, including the hidden catcher. Route: Find the Video on the Page → pass the check yourself → Download from This Page. |

### Round 3 (your 11 points before finalising)
| Your point | What changed |
|---|---|
| Source site, link to the original | Every preview, Downloading row, Downloaded row and Details shows the site as a link ("YouTube ↗"); the full address shows on hover. Downloaded rows also have "Open Original Page". |
| Thumbnails overflowing | Thumbnails sit in a fixed frame: the whole picture is shown (vertical videos too) over a blurred fill, clipped to rounded corners. Nothing spills onto the text. |
| Thumbnail for every item | Downloading and Downloaded rows (playlist entries too) use the video's own picture; the Digby picture only appears if a site gives none. |
| Confusing sidebar | Three places, each one meaning: **New Download** (links you're looking at) → **Downloading** (only what's in progress, paused or failed) → **Downloaded** (finished, with a "N new" badge and a "New" mark). Finished items move across by themselves; starting a download closes its tab and says where it went. |
| Link field | A permanent bar at the top of every screen, separate from the page. |
| Stuck on H.264 | New **Picture** row: "Keep as is" / "Convert to H.264", switch freely. When your usual settings don't fit a video, Digby picks the closest that does and says so, and you can change it. |
| Offer guided extraction early | While a link is being read: "Know this site is tricky, or tired of waiting? — Find It on the Page". |
| Browser sign-in vs Find on the Page | Failure cards show them as two explained options with pros & cons ("Digby tries again as you…" vs "You do what you'd normally do — sign in, pass any check, press play — then click Download"). |
| Plain cause | Failures now name the real problem: "The site wants to check you're human" (CAPTCHA/Cloudflare), "The site is blocking your network" (VPN/data-centre address), "The site refused Digby" (403), sign-in needed, private, removed. |
| Video keeps playing after Download | Closing the page window (by Download or Cancel or ✕) pauses all sound and picture and unloads the page. |
| Unavailable combinations | Choices that can't work with the rest are greyed out and can't be clicked, with the reason on hover ("Not in MOV", "Not at 4K"). Your current choice always stays readable. |

Tests: 266 checks pass.

### Round 4 (your 8 points, 2026-11-15)
| Your point | What changed |
|---|---|
| Details while downloading | Click any Downloading row (or its ⓘ) to open it in place: your choices, the stream chips and size, what the site offered, where it will be saved, plus All Details… / Open Original Page / Copy Link. Playlist entries not read yet say when their details will appear. Details opened mid-download say "Still downloading" instead of "didn't finish". |
| File names by blocks | Settings → Downloads → File names: a live example name, the parts as chips (drag to reorder; click for plain / (brackets) / [square brackets], Move Left/Right, Remove), "Add" buttons for unused parts, a separator choice (Dash, Dot, Space, Underscore), ready-made arrangements, and "Edit as Text…" for anything custom. `NameParts` in the core turns a template into parts and back; empty parts leave no stray separators. 11 new checks. |
| Quieter defaults | Clipboard watching, menu-bar icon and notifications are off by default; settings saved before this are switched off once (`quietDefaults`). Notification permission is only asked for when you turn notifications on. |
| Slow thumbnails | Cause: every row fetched the site's full-size picture again (AsyncImage, no lasting cache, many CDNs say "don't cache", slow over the VPN), and Facebook/X picture links expire. Now `ThumbnailStore`: fetched once, shrunk to 480 px JPEG (≈ 20–40 KB) in ~/Library/Caches, kept decoded in memory, shown without waiting the next time; capped at 60 MB (oldest removed). If the site's picture is gone, a frame of the downloaded file is used. |
| Link bar | Its own strip like a browser address bar: faint brand tint, raised field with a link badge, focus glow, ⌘L hint. New ⌘L ("Go to Link Field") from anywhere. |
| Sidebar | Under Downloading: up to four live rows (progress ring, % and time left, waiting, paused, failed) and "and N more"; clicking one opens Downloading with that row's details open. |
| Narrow window | Buttons never wrap (all button styles keep one line). Downloaded rows adapt: full buttons → icons → the ⋯ menu, which now always holds every action. Checked at the minimum window width (render at 900 px). |
| Extras | Download count on the Dock icon; drag a Downloaded row out to Finder or another app to drop the file. |

Tests: 277 checks pass. Not verified live: dragging the name chips and dragging files out (renders only), the thumbnail cache on real sites.

### Round 5 (the seven ideas, plus Projects, 2026-11-15)
| Feature | What it does | Evidence |
|---|---|---|
| **Projects** | Your own folders for downloads that belong together (Sidebar → Projects → New Project…: name, symbol, folder). Open one: its downloads only (files inside its folder), and links you paste go straight into it ("Saving into Kids' Cartoons ✕" on the link bar). Every download and playlist also has a "Save into" menu. Removing a project never touches its folder. | Rendered |
| **Quick Look** | Click a Downloaded row, press Space to preview; ↑/↓ move (the preview follows), Return opens. Also in the ⋯ menu. | Built; not tried by hand |
| **Date groups** | Downloaded is grouped Today / Yesterday / Earlier This Week / Earlier This Month / by month, with sticky headers. | Rendered |
| **Speed limit** | Settings → Downloads: No limit / 1–50 MB/s, shared by downloads running together (`--limit-rate`, one piece at a time so the limit holds). | Real run with a 2 MB/s limit |
| **Overnight** | The moon button next to Download (and on playlists) makes it wait for the overnight hours (default 1:00–7:00, set in Settings; or "download everything overnight"). Downloading shows a banner with Start All Now, rows show "Overnight · Starts at 1:00", the sidebar too. The Mac is kept awake (not the screen) while anything downloads or waits. | Rendered; the wait itself not run overnight |
| **Watching** | On a playlist or channel: "Watch for New Videos…" (also download the newest 0/1/3/5/10 now; save into a project). New sidebar section lists them with last check, count, Check Now, pause, Save Into, Stop. Checked at launch and every 3 hours while open (newest 60 entries); new videos download with the saved choices. YouTube channel links are pointed at their Videos tab. | Rendered; not run against a live channel |
| **Browser button** | `digby-video://download?url=…` opens the page in Digby for you to choose (never downloads by itself). Chrome/Brave/Edge/Arc/Vivaldi extension (toolbar button + right-click "Download with Digby" / "Download Link with Digby"), installed from Settings → Browser. A bookmark (bookmarklet) works in any browser, Safari included. A real Safari extension needs Xcode (not available here). | Built; scheme registered in Info.plist; not clicked from a browser yet |
| **Part of the video** | "Part of the video": Whole / Only a part, two-handle slider with chapter marks, typed times, chapter menu, Quick cut (nearest key frame, untouched) or Exact cut (re-encoded part, CRF 18). The file name says which part. Size scaled. Found and fixed: cutting uses FFmpeg to fetch, which ignored the Mac's proxy and certificates (timed out behind the VPN); Digby now passes both. | Real runs through the VPN: quick 15.02 s, exact 15.00 s; full app run (exact) verified 15.02 s |
| **Subtitles on the picture** | New subtitle choice "On the picture": one language drawn onto the picture (white, soft outline, system font), picture re-encoded as H.264; WebM refused with one-click alternatives. | Real FFmpeg run: accents and Chinese render correctly |
| **Subtitle translation** | "Translate into…" (20 languages) using macOS's own on-device Translation (macOS 15+): nothing leaves the Mac. A small window shows progress and hosts macOS's language-pack request the first time. If it can't translate, the original subtitles are kept and the download says why. | Builds; SRT reading/writing tested; translation not run live yet |

| **Sort into folders** | Settings → Downloads → Folders: Don’t sort (default) / By month (“2026-11 November”) / By day (“2026-11-15”) / By website / By channel, inside the usual Videos and Music folders. Projects keep their own folder; earlier downloads aren’t moved. Leftover work folders are cleaned one level down too. | 7 unit checks; rendered |

Tests: 300 checks pass (new: folder sorting, parts of a video, subtitles on the picture, translation planning, subtitle files).

### Round 6 (Find the Video window, 2026-11-15)
| Your point | What changed |
|---|---|
| Pick several caught videos | Every caught video has a tick box (the best guess is ticked for you; Tick All). "Use 2 Videos" opens each as its own tab in New Download, named with what it is ("· Video file, 720p"). Fixed underneath: tabs were keyed by page address, so two videos from one page replaced each other. |
| Confusing "Download from This Page" | It never needed the video to play: it reads the page again with this window's sign-in and site checks. It was the big blue button above "Play the video", so it looked like step one. Now "Play the video" is the main step, caught videos appear under it, and the old button is a quiet fallback at the bottom: "Video won't play, or nothing gets caught? … Read Page Again as Me". |

### Round 7 (from the gold-standard review, 2026-11-15)
| Change | What it does | Evidence |
|---|---|---|
| **Play the page out of sight: asked once per site** | The hidden page catch no longer runs silently. The first time a site needs it, the failure card offers "Play the Page Out of Sight" (with pros & cons) and the button "Allow for substack.com"; yes is remembered for that site (`SiteKey`: every Substack author counts as substack.com) and the link is read again. "Don't Offer This for …" hides it for that site. Settings → Privacy → "Playing pages out of sight" lists answered sites (Allow / Don't Allow / Ask Again). Reading with a session remembered from Find the Video still happens without asking (no page is opened). Test runs (`DIGBY_DL_E2E`) count as allowed. | 8 unit checks on site keys; card rendered (`Docs/Screens/failed-out-of-sight-light.png`). Not yet clicked through live on a real site; Settings section not rendered |
| **Find the Video: pages that never load** | Your Facebook post spun forever. The app's log showed why: Facebook redirected the page ~20 times in 2 s and WebKit gave up ("too many redirects", −1007); the catcher didn't handle that kind of failure, so the spinner never stopped over a blank page. A fresh browser loads Facebook fine here, so the likely cause is a stale Facebook sign-in saved in Digby's browser. Now: failed loads stop the spinner and show a plain card over the page — for a loop, "Clear facebook.com in Digby's Browser and Reload" (removes only that site's data) — plus no connection / site didn't answer / secure connection failed, each with Reload. Also: links that open a new window (sign-in pop-ups) open in the same view, app links (fb://) are ignored, and a crashed page reloads itself. | Real run against a redirect loop (httpbin.org/redirect/30): card shown, spinner stopped. The Clear button and the real Facebook post not yet tried |
| **Try Again really retries** | Fixed: "Try Again" on a failure card re-selected the same failed tab and did nothing. A failed tab is now closed and its link read again. | Code path; needs a live click |

Tests: 308 checks pass.

### Round 8 (release fixes, 2026-11-15)
| Change | What it does | Evidence |
|---|---|---|
| **Missing pages** | A page that doesn't exist was explained as "The website seems to have changed" (and set off an engine update), because the engine only says "unable to extract". Digby now asks the page itself (`PageStatus`): a 404/410 becomes "This page doesn't exist", with no engine update and no page-catching routes. | Real: a missing Commons page → "This page doesn't exist" in 12 s (app and CLI). 5 unit checks |
| **Best plays on this Mac** | "Best" is now the highest resolution this Mac plays in QuickTime when saving as MP4/MOV (H.264/HEVC everywhere, AV1 on M3 and later). Higher resolutions stay one click away, and the note says so. Asking for HDR, choosing MKV, converting the picture or burning subtitles keep the highest resolution. | Real YouTube 4K (Blender): M1 → 1080p60 H.264, 288 MB, with "choose 4K to get it anyway". 7 unit checks (M1, M3, MKV) |
| **Crash-safe queue** | Unfinished downloads were saved only on a clean quit. Now every 4 s (only when something changed) and on quit; downloads still waiting for Continue/Discard are kept. | Real: force-killed mid-download, relaunched: entry and partial data still there |
| **Live streams** | Live-now and not-yet-started streams get a plain card ("This is live right now — try again when it ends") instead of an endless or obscure download. Recording live streams is not supported yet. | 5 unit checks; not tried on a real live stream |
| **Already downloaded** | Opening a link you've downloaded before (file still there) says so on the preview, with Show in Finder. | Builds; not exercised live |
| **Quit message** | "Stop downloading and quit?" said nothing half-finished is kept; in fact partial data is kept and offered next time. Fixed. Render mode now quits by itself. | — |
| **Release housekeeping** | `VERSION` 1.1.0; README and website install steps for macOS 15+ ("Open Anyway" in Privacy & Security; right-click → Open no longer works there); `ARCHITECTURE.md` module map and queue section match the code; app E2E harness waits on the queue (downloads leave the main view when they start). | Real app E2E: Internet Archive → verified 360p H.264/AAC, recorded in History |

Tests: 366 checks pass. DMG: `build/DigbyVideoDownloader-<version>.dmg` (4.5 MB; app 12 MB incl. the `digby-dl` helper).

### What I could and couldn't verify on this connection
* Rumble refuses every program on this network (Cloudflare "Just a moment…", even with your Brave session or a browser
  disguise). In the app's catcher *you* pass that check like in any browser, then Digby catches the stream. I can't
  test that step myself (I don't solve bot checks).

## Phase 5 — automation and maintenance (verified)
| Area | State | Evidence |
|---|---|---|
| Update checks | Daily on Stable, 6-hourly on Nightly/Experimental; installs between downloads, never during one; can be turned off | Unit tests (schedule, version comparison) |
| Channels and rollback | Stable / Nightly / Experimental; previous version kept; Roll Back in Settings → Engines; update history | Real: switched yt-dlp to Nightly 2026.11.04 (signature verified), analysed, rolled back to 2026.10.26, analysed |
| Recovery | Site changed → update the extraction engine (Stable, then Nightly) and retry once; dropped connection → retry in 5 s then 30 s, continuing partial data; rate limited → 1 min, then 5 min; private/DRM/region/removed → no pointless retries; at most 3 attempts | Real app against a deliberately broken engine: recognised the problem, installed the genuine engine, re-read the page, showed "Fixed: Updated the extraction engine…" (`Docs/Screens/diagnosing-light.png`, `19-…`). 19 unit checks on the policy |
| Diagnostic reports | Copy Report: problem, site (never the full link), engine versions, recent log — all redacted | Unit test: no secrets, cookies, private link or home folder |
| Bugs fixed | Background update and recovery installing the same engine at once (installs are now idempotent); impossible frame rates from some files ignored | — |

## Phase 6 — Digby integration (verified)
* **Compress with Digby** uses the Compressor's existing "open document" support (no Compressor change needed). Tested
  with the installed Compressor: it received a downloaded video and began analysing it; the download was untouched.
* Proposed future Compressor change (not made): a `digby-compressor://add?path=…&preset=…` URL scheme so the Small File
  profile can hand over a preset.

## Phase 7 — polish and release (done)
* Security review: see `SECURITY.md` (one real fix: subtitle language codes from websites are sanitised before they
  become file names).
* About → Acknowledgements; licences bundled; optional AI advisor defined as a protocol only (`DiagnosticAdvisor`).
* `README.md`; DMG `build/DigbyVideoDownloader-<version>.dmg` (2.7 MB, checksum verified); app 5.8 MB, macOS 14+, arm64.
* Local git repository with all work committed.

## Phase 4 (verified)
| Area | State | Evidence |
|---|---|---|
| **YouTube through Astrill** | Works with your Brave sign-in: full format list (48 formats, up to 4K60) | Real app: analysed → 480p H.264+AAC → verified → recorded in History (`Docs/Screens/`, `16-…`) |
| Sign-in | Per site (YouTube): **your browser's sign-in, read fresh for every run, nothing stored** (Brave/Chrome/Edge/Firefox/Safari/Opera/Vivaldi), or a **sign-in window inside Digby** (private web view; only YouTube + Google account cookies kept, file mode 600). Offered automatically when YouTube asks "are you a bot?"; Settings → Privacy to change or sign out | Browser route tested end to end. The in-Digby window opens and saves cookies, but **the Google sign-in itself is untested** (I can't sign in to your account) |
| Reduced YouTube answers | Detected and explained on the preview ("YouTube sent only a reduced list…") | Seen live: a saved cookie copy went stale and YouTube silently returned only 360p — why browser sign-ins are now read fresh |
| History | SQLite (`History.sqlite`), searchable across everything, filters, Download Again with the same choices, Show in Finder (notices moved/deleted files), Remove record (file kept) or explicitly Move File to Trash | 7 unit checks + real download recorded |
| Settings | Saved (versioned record in user defaults); download folders choosable; file-name template with live preview; playlist subfolders | Renders |
| Unfinished downloads | Remembered on quit (partial data kept); next launch offers Continue/Discard | Code path; quitting mid-download not yet exercised in the app |
| Pause / Resume | Keeps partial data; resumes where it stopped | CLI: paused at 73.6 % → resumed from 73.6 % |
| Profiles | Built-ins + your own (Profiles → Save These Choices…; manage in Settings) | Builds; UI rendered |
| Queue | Global limit + per-site limit (default 1 per site) | Code path |
| Global shortcut | ⌃⌥⌘D downloads the copied link (system hot-key service, no permissions) | Registered at launch; not exercised by keypress |

### Bugs found and fixed in Phase 4
* YouTube's combined HLS formats would have shadowed the better separate sound track; DRC (volume-squashed) and IAMF
  (experimental 3D audio) tracks could be picked. Fixed and tested against the real YouTube answer.
* App froze when a download started: the menu-bar switch wrote its setting back on every scene update, and every write
  re-rendered the scene. Setters now ignore unchanged values. Progress is also limited to 4 updates a second.
* Cookie filter initially kept Gmail/Drive/Pay cookies; now YouTube + Google account only (tested, incl. look-alike domains)._

## Works now (verified on this Mac)
| Area | State | Evidence |
|---|---|---|
| **Engine install** | yt-dlp 2026.10.26, Deno 2.9.8, FFmpeg/FFprobe 9.0.2 installed from official sources into Application Support. yt-dlp: OpenPGP signature on its checksums verified against the pinned key. Deno/FFmpeg: checksums + Apple Developer ID with pinned team (Deno Land `2H4KBF436B`, Martin Riedl `KU3N25YGLU`). Each test-run before use; active version switched atomically; previous kept for rollback | Real install into a test home; log shows each verified install. Tampered checksums and corrupted signatures are rejected (unit tests on yt-dlp's real release files) |
| Stall protection | A connection that stops sending data is cancelled after 45 s and retried (twice) | Added after a real stalled download hung the first install attempt |
| **Analysis** | yt-dlp `-J` → Digby's own model (decoder handles missing codecs, "-1" values, manifests). Codecs a site doesn't report are read from the stream headers with FFprobe, through the Mac's proxy and trusted certificates | Internet Archive (codecs unreported → found H.264/AAC), Wikimedia Commons (31 subtitle languages) |
| **Downloads** | yt-dlp fetch (structured JSON progress) → FFmpeg copy into the chosen file type (converting only what the plan states) → FFprobe check (streams, codecs, size, length) → collision-free move. Metadata embedded; Finder "Where from" set | 5 real downloads: WebM + embedded EN/DE subtitles; MP4 H.264 copy; audio-only MP3 (converted, stated); separate .srt files; second copy saved as “(2)” |
| Cancel | Stops yt-dlp and any FFmpeg it started (process group); work folder removed | Interrupted a 97 MB download at 19%: no engine left running, no partial file |
| **App** | Real engine wired in: first-run engine setup banner, analysis, ready view from real data, queue (max 2 at once), playlist entries analysed when their turn comes, cancel, retry, failure cards from classified errors, notifications, clipboard offer, quit confirmation | `DIGBY_DL_E2E` run of the bundled app: analysed → chose 360p → downloaded → verified (`Docs/Screens/`, `14-…`) |
| Error classification | 18 kinds in plain English (bot check, private, login, region, rate limit, blocked, removed, unsupported site, outdated engine, disk full, DRM…) | Unit tests use the real messages seen from YouTube and Vimeo |
| CLI | `digby-dl engines [install|check|update|rollback]`, `analyse`, `download` | Used for all end-to-end tests |
| Tests | **189 checks** pass (`swift run digby-dl-tests`) | Run by every `Scripts/build_app.sh` |

## Found during Phase 3
* YouTube refused this Mac ("Sign in to confirm you’re not a bot") and Vimeo returned 403: the 127.0.0.1:3213 proxy is
  Astrill (OpenWeb). Solved for YouTube in Phase 4 with your sign-in. Vimeo still refuses this connection (no sign-in
  route built for Vimeo yet).
* **First launch of a new yt-dlp takes ~34 s** (macOS checks its 124 MB of files once); later starts take 0.3 s. The installer's
  test run absorbs this, so it never happens during a download.
* Sites often don't report codecs (Internet Archive) or offer only combined files (Wikimedia): handled by stream inspection
  and "audio only from the smallest combined file" (stated in the plan).

## Open issues and unfinished work (as of 2026-11-15)
* **Needs a person to try (see the manual checklist in `TESTING.md`):** everything I can't drive from here — clicks in
  windows, sign-ins, CAPTCHAs, the hot-key, browser buttons, Quick Look, drag-out, overnight, Watching, translation.
* **Rumble and Vimeo:** blocked by Cloudflare on this network; route is Find the Video → pass the check → Read Page Again as Me.
* **Not built (skipped for now by you):** Developer ID signing/notarisation and app self-update, ⌘V downloading straight away,
  Intel, translations, App Store. The app is ad-hoc signed: first launch needs "Open Anyway" (README).
* **Not built yet:** recording live streams; moving the queue out of `AppModel` into the core.
* Publishing (public repo, GitHub release, family website, neutral domain) waits for your go-ahead.

## Decisions made (by you)
1. Downer = github.com/dsameendra/Downer (reviewed). 2. Free, public, MIT. 3. Tagline: **"Anything you find. Yours to keep."**
4. Plain-English explanations for every choice.
5. (2026-11-15, from `GOLD_STANDARD_REVIEW.md`) Default quality = **best that plays on this Mac**; "Highest available"
   becomes the alternative. Not built yet. Skipped for now: Developer account/Xcode, ⌘V downloads straight away, Intel,
   languages, App Store.

## Technical decisions (Phase 2–3)
| Decision | Reason |
|---|---|
| Digby picks exact stream IDs from the full list | Deterministic, testable; never a silent downgrade |
| yt-dlp joins streams into MKV, then FFmpeg copies into the chosen type | One lossless intermediate holds anything; conversions happen in one place, only when the plan says |
| MP4 refuses VP9; Opus into MP4 → AAC 256 kbps (Apple's encoder), stated | Compatibility promise of MP4 |
| Engines downloaded on first run, not bundled | 5 MB app; always-current extractor; no GPL redistribution |
| `--ignore-config --no-update --no-cache-dir` on every yt-dlp run | A personal yt-dlp setup can't change Digby's behaviour; Digby manages versions |
| Work folder hidden inside the destination folder | Final move is an atomic rename on the same disk |
| FFprobe gets the Mac's proxy + trusted certificates | Analysis works on office/proxied networks |
| No link to the Compressor's website in the app | Its URL contains a personal account name |

## Known limitations
* Unsigned (ad-hoc) app: first launch needs right-click → Open. Developer ID signing needs an Apple Developer account.
* No Xcode: no Safari extension yet; tests are an executable rather than XCTest.
* My window snapshots can't capture the vibrant sidebar (renders fine on its own).

## Compress after downloading (branch `updates-2026-11`, 2026-11-26, not committed)
* "After downloading" row (single video and playlist screens): Keep as Downloaded / Compress with Digby; How small
  (Light, Balanced, Small, Smallest, Fit a Size in MB, Compressor's Settings); move the big download to the Trash once the
  smaller copy is made and checked (on by default). Remembered in `AppSettings.compressAfter`; copied onto each download
  when it starts. Audio-only downloads are never sent.
* Hand-off: `CompressHandoff` writes a JSON note to `~/Library/Application Support/Digby Video Compressor/Handoff/`, then
  opens the file in the Compressor without bringing it forward. The Compressor (`Handoff.swift`) uses a matching note under 10
  minutes old once, starts at once, uses `OriginalReplacer` when asked, and never changes its own saved settings for it.
  Opening a video any other way is unchanged. Override the folder with `DIGBY_HANDOFF_DIR` for tests.
* Downloaded: a Compress icon on each video row; the ⋯ menu has Compress Now and Open in Digby Compressor.
* Verified: both build, 366 + 87 checks pass, note round trip tested in isolation. Not yet tried in the real apps.
* Known: when the Compressor replaces a .webm/.mkv download, the smaller file is .mp4, so that History row shows "File moved".
* Size estimates (2026-11-26): each How small option shows "≈ low–high MB", a share of the download size by the site's
  codec (`CompressAfter.Size.estimate`). The shares are judgment, not measured on real downloads; tune them from user reports.
* Compression history (2026-11-26): the Compressor writes `HandoffResult` notes (compressing → done/skipped/failed/cancelled)
  to `…/Digby Video Compressor/Handoff/Results/`, only for videos the Downloader sent. The Downloader reads them every 3 s
  (`applyCompressionResults`), stores a `CompressionRecord` in `DownloadDetails.compression` (no schema change) and points
  the entry at the smaller file when the original was trashed. UI: status chip and "X (was Y)" in Downloaded, a Compressed
  filter, total saved, and a "Made smaller" card in Details. Round trip tested in isolation; not yet tried in the real apps.

## Resume after quit (2026-11-26, uncommitted on updates-2026-11)
* Unfinished downloads were already saved on quit and every 4 s (`Unfinished downloads.json`), so a force quit, crash or restart loses nothing. New: each entry also records why it stopped (`stoppedNote`), a failure's plain reason (`failure`) and its "Compress with Digby" choice (`compressAfter`, which was lost on resume before). Downloads that finished or were cancelled in the same session go to `Last session.json` (removed once nothing is unfinished).
* On reopen, a summary strip (`ResumeBanner` in `Views/ContentView.swift`) says what finished, what quitting stopped, what failed (with the reason) and what was cancelled, with Resume All, Details (per-row Resume / Try Again / Remove) and Dismiss.
* Fixes: Dismiss (was "Discard") used to delete every `.digby-download-*` work folder, including those of downloads running at that moment, and missed project folders. It now removes only the dismissed downloads' folders (`Leftovers.removeWork`). Engines left running by a force quit (orphans from the `Tools` folder) are stopped at launch before resuming (`Leftovers.stopOrphans`).
* Code: `DigbyDownloadCore/Support/LastSession.swift` (new), `App/AppSettings.swift`, `App/AppModel.swift` (Unfinished downloads section), `Views/ContentView.swift`, render state `resume` in `App/DebugRender.swift`. 376 checks pass (10 new).
* Undo: delete `LastSession.swift`, then `git diff` those files and revert the hunks named above (other sessions' uncommitted work is in the same files). Old `Unfinished downloads.json` files still load, and the new fields are optional.
