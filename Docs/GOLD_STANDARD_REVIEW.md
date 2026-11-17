# Digby Video Downloader — Gold-Standard Review

_2026-11-15. Competitive research, UX benchmark, gap analysis, target specification and roadmap. Nothing in this
document has been implemented; it is a plan for decisions._

---

## 0. The verdict in one page

**Where Digby already leads the category.** Its *engine* is more careful than any competitor examined: it picks exact
streams rather than trusting a sort order, never downgrades or re-encodes without saying so, checks every finished file
with FFprobe, installs its engines with signature checks and keeps the previous version for rollback, runs a recovery
chain before showing an error, and explains failures in plain words. "Find the Video on the Page" is the same idea as
Downie's user-guided extraction, which is the feature that makes Downie the reference on the Mac. Nobody else combines
these. Keep all of them.

**Where it is far from the standard.** Four problems would stop a reviewer before they reached any of the strengths:

1. **People can't trust it, install it, or keep it updated.** The app is ad-hoc signed and not notarised. Since
   macOS 15 the old "right-click → Open" trick no longer works for such apps: users have to go to System Settings →
   Privacy & Security → Open Anyway, which is exactly what malware tells people to do. Downloaders are a category with a
   bad safety reputation (adware installers, "is PullTube safe?" articles), so this hurts more here than for most apps.
   The app also has **no way to update itself**: the engines update, the app never does. It is arm64 only. *None of
   the four major paid competitors ship like this.*
2. **The main path asks too many questions.** Every link opens a seven-row decision page (type, resolution, video
   format, brightness range, file type, sound language, subtitles). The explanations are excellent, but most people
   should never see them. Downie's whole reputation rests on one thing: press ⌘V and the download starts. Digby can
   match that and still keep its control, but today it doesn't. On an M1/M2 Mac, the default "Best" produces a 4K AV1
   file *that QuickTime on that Mac can't play*. The app warns about it honestly, but it shouldn't be the default.
3. **Features are spreading faster than they are checked.** In about 36 hours of work, the app gained Projects,
   Watching, Overnight, folder sorting, a name-block builder, tabs-*or*-list, subtitle burning and translation, and
   Quick Look. Many are marked "rendered" or "built, not tried". Three of them overlap (Projects, "Save into" and
   folder sorting all decide where a file goes). A reviewer will find the seams.
4. **The core is held together by one large class.** `AppModel` (990 lines, `@MainActor`) contains the queue
   scheduler, the recovery chain, drafts, watching and settings plumbing. The `Queue/DownloadQueue (actor)` that
   `ARCHITECTURE.md` describes doesn't exist. The queue is saved **only on a clean quit** (`saveQueue()` is called
   from the quit path), so a crash, force quit, power cut or macOS restart for an update loses every waiting and
   running download.

**Honest distance from the goal:** the *engine* is about 80 % of the way to best in class. The *product* (trust,
distribution, first-run, the default flow, accessibility, localisation, reliability under real-world failure) is
about 45 %. The gap is not features. It is depth, defaults and polish on what already exists.

**The five decisions to make before writing more code** (details in §F):
1. Pay for an Apple Developer account ($99/year) for notarisation, Sparkle updates and a Safari extension. Without
   it, "gold standard" is out of reach on the Mac.
2. Choose the default interaction: **"⌘V downloads immediately with your usual choices"** (recommended) or "⌘V
   opens the choices".
3. Choose the default quality rule: **"best that plays on this Mac"** (recommended) or "highest resolution
   available".
4. Freeze features until everything already built has been verified live, and cut or merge the overlaps.
5. Decide the scope of "any video I can play" in a product released to the public: keep the hidden off-screen page
   catcher on by default, or make it ask first (recommended: ask the first time per site; see §C.6).

---

## 1. Method and confidence

* **Codebase:** read every document in `Docs/`, the screens in `Docs/Screens/`, and the sources (11.7k
  lines of Swift across 63 files). Specific findings cite files.
* **Competitors:** official product pages, GitHub READMEs, and review and forum coverage (sources in §7). Some sites
  blocked automated reading (VideoHelp, the Stacher site, Downie's changelog), so a few competitor entries come from
  well-documented knowledge rather than a fresh read this session.
* **Confidence marks in the matrix:** ✅ verified this session from an official or primary source · ☑️ well documented
  (long-standing, widely reported) but not re-read this session · ❔ unknown or unconfirmed · ❌ absent (verified or
  well documented) · ◐ partial.
* Pricing changes often. Figures are as published on the sources' pages in November 2026.

---

## 2. The landscape

| Product | Type | Platforms | Price model | Engine | One-line character |
|---|---|---|---|---|---|
| **Downie 4** (Charlie Monroe) | Native Mac | macOS 13+ (15+ rec.) | $19.99 per major version, 3 Macs; or Setapp ✅ | Own extractors + yt-dlp ☑️ | The reference Mac downloader: ⌘V and it's done, weekly updates, user-guided extraction ✅ |
| **PullTube** (MyMixApps) | Native Mac | macOS 11/13+, Intel + Apple Silicon ✅ | Paid license (2 Macs), 7-day full trial, Setapp ✅ | yt-dlp ☑️ | Downie's cleaner-looking rival; trim before download, "Download later" ✅ |
| **4K Video Downloader Plus** | Cross-platform (Qt) | macOS 12+, Win, Ubuntu ✅ | Free with limits (reported 10–30/day); Lite €18.75/yr; Personal €31.25; Pro €50 ✅ | Own | Most features on paper (8K, 360°, subscriptions, "Smart Mode", AI vocal removal); recurring breakage and licence complaints ✅(reported) |
| **Stacher 7** | Electron yt-dlp GUI | Mac, Win, Linux ✅ | Free + Premium (library, themes, player) ✅ | yt-dlp, installed from official sources ✅ | Power-user front end with "Pro Mode" exposing yt-dlp options ✅ |
| **Parabolic** (Nickvision) | Native GTK/WinUI | Linux, Windows, macOS builds ✅ | Free, MIT ✅ | yt-dlp | Best-designed open-source front end; localised through Weblate ✅ |
| **Open Video Downloader** | Tauri yt-dlp GUI | Mac, Win, Linux ✅ | Free, AGPL ✅ | yt-dlp, self-updating ✅ | Simple, cross-platform; auto-updates app *and* yt-dlp ✅ |
| **MacYTDL** | AppleScript yt-dlp GUI | macOS 10.10+, notarised ✅ | Free | yt-dlp + FFmpeg + Deno ✅ | Ugly but deep; macOS Service; per-download log files ✅ |
| **JDownloader 2** | Java download manager | All ✅ | Free; installer history of bundled offers ✅ | Own plugins | Link grabber, clipboard watching, packages, remote control ☑️ |
| **yt-dlp** | CLI | All | Free (Unlicense) | — | The engine almost everyone above depends on |
| **Video DownloadHelper** | Browser extension + companion app | Browsers | Freemium ☑️ | Own | Catches whatever plays in the browser ☑️ |
| **cobalt** | Web service | Web | Free, no ads ☑️ | Own | The UX benchmark for "paste and nothing else" ☑️ |
| **Seal** | Android | Android | Free, GPL | yt-dlp ✅ | Best mobile yt-dlp UX; custom command templates ✅ |

**What the market tells us**
* The only Mac apps people pay for (Downie, PullTube) win on **speed of the common case** and **speed of fixes**:
  reviewers repeatedly praise Downie for shipping fixes within about a day of YouTube changes (reported, Setapp/Sweet
  Bits).
* The most complained-about product (4K Video Downloader) loses on **reliability and trust**: failure waves after
  YouTube changes, ads in the free tier, licences that stopped working (Trustpilot, TidBITS, tech press).
* Open-source front ends are free but feel like forms bolted onto yt-dlp: options are named after flags.
* **No one** explains choices in plain words, checks the finished file, or recovers automatically before reporting an
  error. That is Digby's opening, and it already holds it.
* YouTube is a moving target: yt-dlp now needs a JavaScript runtime (Deno) and PO tokens for some clients, and some
  clients are being forced onto SABR streaming ✅ (yt-dlp wiki and issues). Digby already manages Deno. **Engine
  freshness is a product feature, not maintenance.**

---

## A. Competitive feature matrix

Digby column: ✅ = built and verified live · ◐ = built but not verified live, or partial · ❌ = absent.

### A.1 Downloading

| Capability | Digby | Downie | PullTube | 4KVD+ | Stacher | Parabolic | OVD | MacYTDL | JDown. | yt-dlp | Opportunity |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Sites supported | yt-dlp (~1,800) + page catcher | 1,000+ ✅ | 1,000+ ✅ | ~10 named ✅ | yt-dlp ✅ | yt-dlp ✅ | yt-dlp ✅ | yt-dlp ✅ | Plugins ☑️ | ✅ | Show *verified* site status (see D.Differentiators) |
| Up to 4K/8K, 60 fps, HDR | ✅ (HDR choice explicit) | ✅ 4K ✅ | ✅ 8K, HDR? ❔ | ✅ 8K ✅ | ✅ | ✅ | ✅ | ✅ | ◐ | ✅ | HDR → SDR tone-map option is rare |
| Codec choice (AVC/HEVC/AV1/VP9) | ✅ plain words | ◐ (post-process to MP4) ☑️ | ✅ ✅ | ◐ | ✅ raw | ◐ | ◐ | ✅ raw | ❌ | ✅ | Digby's best area |
| "Plays on this Mac" awareness | ✅ (AV1 decode check) | ❔ | ❔ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | **Unique.** Make it the default |
| Audio only, conversion | ✅ M4A/MP3/FLAC/WAV/Opus | ✅ ✅ | ✅ MP3/M4A ✅ | ✅ MP3/M4A/OGG ✅ | ✅ | ✅ ✅ | ✅ | ✅ | ◐ | ✅ | — |
| Audio language / dubbed tracks | ✅ | ❔ | ❔ | ❔ | ◐ | ❔ | ❔ | ◐ | ❌ | ✅ | Digby leads |
| Playlists, select items | ✅ | ✅ ☑️ | ✅ ✅ | ✅ ✅ | ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ | ✅ | — |
| Channels / subscriptions | ◐ Watching (not run live; only while app open) | ☑️ | ❔ | ✅ ✅ | ✅ ✅ | ❔ | ❌ | ❌ | ❌ | ✅ (archive) | Background checking |
| Batch paste | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ | ✅ | — |
| Subtitles (manual + auto, embed/separate) | ✅ | ✅ ☑️ | ✅ incl. auto ✅ | ✅ SRT, 50+ ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ ✅ | ❌ | ✅ | — |
| Burn-in subtitles | ◐ | ❔ | ❔ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Rare |
| On-device subtitle translation | ◐ (not run live) | ❔ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Unique if it works |
| Metadata embed, Finder "Where from" | ✅ | ☑️ | ❔ | ◐ | ✅ | ✅ ✅ | ✅ ✅ | ✅ ✅ | ❌ | ✅ | — |
| Thumbnail save/embed | ◐ (cached for UI; embed?) | ☑️ | ✅ ✅ | ☑️ | ✅ | ❔ | ❔ | ✅ ✅ | ❌ | ✅ | Embed artwork in audio |
| Chapters (embed / split / pick) | ✅ embed; ◐ pick part by chapter | ❔ | ❔ | ❌ | ✅ | ❔ | ❔ | ❔ | ❌ | ✅ | Split audio into tracks by chapter |
| Trim before download | ◐ (quick/exact, verified via CLI) | ❌? ❔ | ✅ ✅ | ❌ | ✅ | ✅ (time frame) ☑️ | ❌ | ❌ | ❌ | ✅ | — |
| SponsorBlock (skip/mark segments) | ❌ | ☑️ (reported) | ❔ | ❌ | ✅ ☑️ | ✅ ☑️ | ❔ | ❔ | ❌ | ✅ | **Gap.** Mark as chapters by default; never cut silently |
| Live streams (record, from start) | ❌ (not handled) | ☑️ | ❔ | ◐ Twitch recordings ✅ | ✅ | ❔ | ❔ | ❔ | ❌ | ✅ | **Gap** |
| Scheduling | ◐ Overnight window | ❔ | "Download later" ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | — | — |
| User-guided extraction (in-app browser) | ✅ Find the Video on the Page | ✅ ✅ | ❌ | ◐ in-app browser for sign-in ✅ | ❌ | ❌ | ❌ | ❌ | ◐ | ❌ | Shared lead with Downie |
| 3D / 360° | ❌ | ❔ | ❔ | ✅ ✅ | ◐ | ❔ | ❔ | ❔ | ❌ | ◐ | Low priority |
| Verify finished file | ✅ FFprobe | ❌ ☑️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ◐ CRC | ❌ | **Unique** |

### A.2 Workflow and usability

| Capability | Digby | Downie | PullTube | 4KVD+ | Stacher | Parabolic | OVD | MacYTDL | JDown. | Opportunity |
|---|---|---|---|---|---|---|---|---|---|---|
| ⌘V starts a download with no further step | ❌ (opens choices) | ✅ ✅ | ◐ | ✅ Smart Mode ✅ | ❌ | ❌ | ❌ | ◐ Service ✅ | ◐ link grabber | **Most important UX gap** |
| Clipboard detection | ◐ off by default, offers | ☑️ | ❔ | ☑️ | ❔ | ❔ | ❔ | ✅ Service ✅ | ✅ ☑️ | — |
| Drag and drop | ✅ | ✅ | ✅ ✅ | ✅ | ✅ | ❔ | ❔ | ❔ | ✅ | — |
| Safari extension | ❌ (bookmarklet only) | ✅ ✅ | ✅ ✅ | ❌ | ❌ | ❌ | ❌ | ◐ Service | ❌ | **Gap**; needs Xcode + dev account |
| Chrome/Firefox extension | ◐ Chrome family, not clicked live | ✅ ✅ | ✅ ✅ | ❌ | ❔ | ✅ ✅ | ❔ | ❌ | ◐ | Firefox missing |
| macOS Services / Share menu | ❌ | ❔ | ❔ | ❌ | ❌ | ❌ | ❌ | ✅ ✅ | ❌ | Cheap win |
| Shortcuts / App Intents | ❌ | ❔ | ❔ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Differentiator |
| Global hot-key | ◐ (not pressed live) | ❔ | ❔ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| Queue: pause / resume / retry / reorder | ◐ pause+resume ✅ CLI, reorder? | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ | — |
| Queue survives crash / restart | ❌ (clean quit only) | ❔ | ❔ | ☑️ | ❔ | ❔ | ❔ | ✅ resume ✅ | ✅ ☑️ | **Gap** |
| History, search, re-download | ✅ | ✅ (iCloud sync ✅) | ✅ ✅ | ✅ | ✅ | ✅ | ❔ | ❌ | ✅ | iCloud sync |
| Duplicate detection | ◐ (within a paste; not against History) | ❔ | ❔ | ❔ | ✅ archive | ❔ | ❔ | ❔ | ✅ ☑️ | Check History + disk |
| File naming templates | ✅ block builder | ☑️ | ❔ | ◐ | ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ | — |
| Per-type / per-project folders | ✅ | ☑️ | ❔ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ | ✅ packages | Merge overlapping concepts |
| Notifications | ✅ (opt-in) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ | — |
| Concurrent downloads + per-site limit | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ ✅ | ✅ | — |
| Speed limit | ✅ | ❔ | ❔ | ❔ | ✅ | ❔ | ❔ | ✅ ✅ | ✅ ✅ | — |
| Hand-off to converter | ✅ Compressor | ✅ Permute ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Family advantage |

### A.3 Advanced and app quality

| Capability | Digby | Downie | PullTube | 4KVD+ | Stacher | Parabolic | OVD | MacYTDL | JDown. |
|---|---|---|---|---|---|---|---|---|---|
| Browser cookies (sign-in) | ✅ read fresh, per site | ☑️ | ❔ | ◐ in-app sign-in ✅ | ✅ | ✅ ☑️ | ✅ cookie file ✅ | ✅ ✅ | ◐ |
| In-app sign-in window | ✅ (Google sign-in not tested) | ✅ | ❔ | ✅ ✅ | ❌ | ❌ | ❌ | ❌ | ◐ |
| Proxy | ◐ system proxy only | ❔ | ✅ HTTP/SOCKS ✅ | ✅ ✅ | ✅ | ❔ | ❔ | ✅ ✅ | ✅ |
| Custom engine arguments | ❌ | ❌ | ❌ | ❌ | ✅ Pro Mode ✅ | ◐ | ❔ | ✅ ✅ | n/a |
| Exact format table | ✅ See Every Format | ❔ | ✅ | ❌ | ✅ | ◐ | ✅ | ✅ ✅ | n/a |
| Engine self-update + rollback | ✅ (signed, pinned, rollback: unique) | ✅ weekly ✅ | ☑️ | ✅ | ✅ ✅ | ◐ | ✅ ✅ | ✅ ✅ | ✅ |
| **App** self-update | ❌ | ✅ ☑️ | ✅ ☑️ | ✅ | ✅ | ◐ | ✅ ✅ | ✅ ✅ | ✅ |
| Signed + notarised | ❌ ad-hoc | ✅ | ✅ | ✅ | ❔ | ❔ | ❔ | ✅ ✅ | ◐ |
| Intel support | ❌ | ✅ | ✅ ✅ | ✅ | ✅ | ✅ | ✅ ✅ | ✅ ✅ | ✅ |
| Localisation | ❌ English only, strings in code | ☑️ several | ❔ | ✅ many | ❔ | ✅ Weblate ✅ | ❔ | ◐ 5 (3 outdated) ✅ | ✅ many |
| Plain-English error causes + routes | ✅ unique | ◐ | ❌ | ❌ | ❌ raw logs | ❌ | ◐ | ◐ log per download ✅ | ❌ |
| Redacted diagnostic report | ✅ | ❔ | ❔ | ❔ | ❌ | ❌ | ❌ | ◐ | ✅ log upload |
| Privacy (no telemetry) | ✅ none | ◐ anonymous stats (opt) ✅ | ❔ | ❌ ads ✅ | ❔ | ✅ | ❔ | ✅ | ◐ |

---

## B. UX/UI benchmark — what to learn and what to avoid

### Downie — **the default flow is the product**
* **Learn:** ⌘V anywhere in the app starts a download immediately with the user's usual post-processing ✅. The choice
  ("MP4 for iPhone", "audio only", "send to Permute") is made once and remembered, and can be changed per item
  *afterwards* ✅. That is the right model: decisions are a preference, not a gate. User-guided extraction ✅ is the
  correct answer to "the site isn't supported". Fast fixes create trust.
* **Avoid:** reviewers find the add button hidden in a corner and the queue "technical and confusing to newcomers" ✅
  (Sweet Bits). Licences tied to a major version annoy people at upgrade time.

### PullTube — **trim is a first-class verb**
* **Learn:** click the duration to enter trim mode ✅; "Download later" as a separate list ✅; proxy support ✅; licence
  for two Macs plus a fully working 7-day trial ✅.
* **Avoid:** minimal explanations; quality options appear as raw lists.

### 4K Video Downloader Plus — **Smart Mode is right, the business model is wrong**
* **Learn:** "Smart Mode" (format, quality, subtitles and folder set once, then every link downloads with them) ✅ is
  the same insight as Downie, made visible with a toggle. Subscriptions for channels ✅. In-app browser to sign in ✅.
* **Avoid:** daily download limits, ads, licences that stop working, waves of failures after site changes ✅ (reported).
  Every one of these destroys trust. Digby's free, no-telemetry, self-healing position is the direct answer:
  **say so on the website and in the About box.**

### Stacher / Open Video Downloader / Parabolic — **don't name options after flags**
* **Learn:** Stacher's separate "Pro Mode" ✅ keeps advanced options out of the main path. OVD updates both the app and
  yt-dlp ✅. Parabolic shows that localisation through Weblate ✅ is cheap for an open-source project.
* **Avoid:** form-style UIs with dozens of options visible, and errors shown as raw yt-dlp output.

### MacYTDL — **depth in unglamorous places**
* **Learn:** a macOS Service that sends selected text or a link to the app ✅; one log file per download ✅ (troubleshooting
  is per item, not per app session); notarised even as a hobby project ✅; a help document.

### JDownloader — **the link grabber model**
* **Learn:** copied links collect in a "link grabber" holding area, grouped into packages, before you commit ☑️. That
  is what Digby's "New Download" drafts are; the lesson is to let many links pile up without each one demanding a
  decision.
* **Avoid:** installer offers ✅, Java UI, overwhelming settings.

### cobalt — **the radical baseline**
* **Learn:** a single field and a single button, with a "mode" (auto / audio / mute) as the only choice ☑️. Any
  Digby design should pass the test: *could a first-time user download a video without reading anything?*

### Cross-cutting patterns the best software uses
1. **Decide once, apply forever, change per item afterwards** (Downie, Smart Mode).
2. **One obvious entry point** that is always visible (Digby's permanent link bar is good; ⌘L is good).
3. **Progress that answers "how long?" and "is it stuck?"**, not only a percentage.
4. **Errors as next steps, not as messages.** Digby already does this better than anyone.
5. **Native Mac grammar:** toolbar, sidebar source list, Inspector, standard menus, Services, Share, Shortcuts,
   Quick Look, drag out, undo. Digby has many of these; Services, Shortcuts, Share, Inspector and undo are missing.

---

## C. Gap analysis — Digby against the field

### C.1 Strengths to preserve (don't rebuild these)
* `FormatSelector`: deterministic exact-ID plans, tested from fixtures, no silent downgrade.
* Copy-first post-processing with a stated conversion, plus FFprobe verification before "done".
* `DependencyManager`: OpenPGP-verified yt-dlp, pinned Developer-ID teams for Deno and FFmpeg, staged install, atomic
  switch, rollback. This is better than every competitor examined.
* The recovery chain (engine update → browser sign-in → remembered session → page catch → explained failure).
* `ErrorClassifier` with 18 plain-English kinds, `Redactor`, redacted reports, no telemetry.
* "Find the Video on the Page".
* The explanation system ("Pros & cons" on every choice) and greyed-out impossible combinations.
* Process hygiene: argument arrays, `--` before URLs, `--ignore-config`, process-group cancel.

### C.2 Missing essential features
| Gap | Why it is essential | Evidence |
|---|---|---|
| Notarised Developer ID build | macOS 15+ makes unsigned apps a System Settings detour; trust is the category's main weakness | `Docs/IMPLEMENTATION_STATUS.md` "ad-hoc signed" |
| App self-update (Sparkle 2, EdDSA-signed appcast) | Fixes must reach users within a day, like Downie's | No updater for the app in `Sources/` |
| Queue saved continuously | Crash, force quit or restart loses every pending download | `AppModel.saveQueue()` only on quit (`AppModel.swift:251`) |
| ⌘V-to-download (quick mode) | The competitive baseline set by Downie and 4KVD Smart Mode | `ComposerView` always leads to the choices page |
| Duplicate detection against History and disk | "You already downloaded this on 3 Nov — Open / Download Again" saves time and disk | Only in-paste duplicates (`AppModel`) |
| Live streams | Pasting a live link must not hang or fail obscurely: offer "Record from now", "From the start" (where allowed) or "Wait until it ends" | No `is_live`/`live_status` handling in `Sources/` |
| Safari extension | Safari is the default Mac browser; a bookmarklet is not a product feature | Needs Xcode + Developer ID |
| Intel or universal build | Intel Macs are still in use in 2026; every competitor supports them | arm64 only (`ARCHITECTURE.md`) |

### C.3 Missing advanced features
* **SponsorBlock**, default "mark sponsor segments as chapters" (non-destructive), with "remove them" as an explained
  option. Uses only the public SponsorBlock API; nothing is sent but the video ID (say so).
* **Proxy settings per app** (HTTP/SOCKS) beyond the system proxy, and **per-site network routes**. This matters to
  the actual user (Astrill) and to every user in a filtered network.
* **Custom engine arguments** in a "For Experts" panel, validated against an allow-list (no `--exec`, no output paths
  outside the destination, no `--config-location`). Stacher and MacYTDL users expect this.
* **Download archive** for Watching, so a channel never re-downloads items after History is cleared (yt-dlp's
  `--download-archive` semantics, stored in Digby's own database).
* **Background watching** through a login item / `SMAppService` helper, so channels are checked when the window is
  closed. Today Watching only runs while the app is open.
* **Split audio by chapter** (albums, mixes, audiobooks), with track numbers and artwork embedded.
* **Audio loudness normalisation** as an explained, opt-in conversion for audio downloads.
* **Rate-limit politeness** (`--sleep-requests`, `--sleep-interval` for big playlists), surfaced as "Be gentle with
  this site" when a 429 occurs.
* **Per-download log**, viewable and exportable from the item (MacYTDL's best idea).

### C.4 UX/UI deficiencies (specific)
1. **The ready page is a gate.** Seven rows of decisions for every link. Fix: show a one-line *plan sentence* and a
   Download button ("1080p · MP4 · plays everywhere · 587 MB"), with "Change…" revealing today's selector. In quick
   mode, ⌘V skips the page entirely and the item appears under Downloading.
2. **Default "Best" can give an unplayable file** on M1/M2 (`Docs/Screens/ready-light.png`: 4K AV1 with an
   orange warning). Default rule should be *"best that plays on this Mac"*, with "highest available" one click away
   and explained.
3. **"Analyse"** is an engineer's verb, and British spelling in an English-only UI. Use "Get Video" or simply make
   pressing Return start the read. The button disappears in quick mode.
4. **Too many ways to organise.** Projects, "Save into", folder sorting (month/day/site/channel), and per-type
   folders all decide where a file goes. Merge into one concept: **Destinations**: "Videos", "Music", plus any
   user-made destination (today's Projects) with its own optional sorting rule.
5. **Tabs *or* list** for drafts is a mode switch most people will never understand. Pick the sidebar list (it
   scales; tabs don't past ~6) and remove the toggle.
6. **Explanations everywhere.** "Pros & cons" links next to every row add visual noise for people who already
   understand. Keep them, but show them in a single Inspector pane for the focused row, not inline under each row.
7. **No Inspector.** Details exist as a sheet and inline expansion. A trailing `.inspector` (macOS 14) showing the
   selected item's details, log and actions is the native pattern and unifies three current presentations.
8. **Window title area** ("Digby Video Downloader" in grey text above the link bar) wastes height; use a unified
   toolbar with the link field *in* the toolbar, like Safari's address field.
9. **Undo** is missing for remove/clear actions (`UndoManager`), and there is no "Clear Finished" with undo.
10. **First run:** engine installation (124 MB yt-dlp, ~34 s first launch) must be a calm, single progress state that
    lets the user paste a link *while* it installs (queue it), not a banner they have to wait through.
11. **Empty states** should teach the three entry points (paste, drag, browser button) and the hot-key, once.

### C.5 Accessibility deficiencies
* 53 accessibility modifiers across ~6,000 lines of UI. Custom controls (`Chip`, `PillButton`) are labelled with
  selected traits, which is good, but:
  * Selection rows of chips are not grouped as a single control with a label ("Resolution, 1080p selected, 9 options").
    VoiceOver users will hear long flat lists. Use `.accessibilityElement(children: .contain)` with a container label,
    or a native `Picker` with a custom style.
  * 38 fixed `.font(.system(size:))` calls do not follow the user's text size preference (macOS 14 sidebar sizes /
    accessibility text size). Use text styles throughout.
  * No `accessibilityRotor` for the Downloaded list (jump by date group or by site).
  * Progress rings need `accessibilityValue` with percent *and* time left, and must announce completion
    (`AccessibilityNotification.Announcement`).
  * Increase Contrast (`colorSchemeContrast`) and Differentiate Without Colour are not handled; status uses colour
    (orange text for "Private video").
  * Full Keyboard Access: chip rows need arrow-key navigation and visible focus rings; no evidence of `.focusable`
    work.
* No accessibility audit has been done with VoiceOver on a real build (render mode can't test it). **Plan a manual
  VoiceOver + Keyboard-only pass on every screen as a release gate.**

### C.6 Architectural limitations
1. **`AppModel` god object** (990 lines, ~140 members). Extract into the core: `DownloadQueue` (actor: scheduling,
   limits, persistence), `RecoveryCoordinator` (the chain), `DraftStore`, `WatchService`. The app keeps a thin
   `@Observable` view model that observes them. This also lets the CLI and a future background helper use the same
   queue. *This is a refactor, not a rewrite: the logic stays, its home changes.*
2. **Persistence:** move the queue into the existing SQLite database (`HistoryStore` already has migrations), written
   on every state change, so crash recovery is free. Drop `Unfinished downloads.json`.
3. **Docs drift:** `ARCHITECTURE.md` lists `Queue/`, `Integration/`, `Compatibility` modules that don't exist. Update
   it; reviewers and future contributors read it first.
4. **Strings are hard-coded** in views and in `Explanations.swift`. Moving to a String Catalog (`.xcstrings`, works
   with SwiftPM 5.9+ resources) is easiest now, before more text is written. Explanations need pluralisation and
   number formatting (`Measurement`, `ByteCountFormatter`) per locale.
5. **Tests:** 300 checks in an executable are a good core. Missing: UI-state tests of the view model (possible once
   the queue moves to the core), a fixture corpus of real `yt-dlp -J` answers per major site refreshed weekly, and a
   "canary" job that runs real downloads of public test media against the latest yt-dlp nightly to catch breakage
   before users do.
6. **The hidden page catcher** loads and plays an arbitrary page off-screen without the user seeing it. It is clever
   and within the rules (no bypassing, the user can watch the video), but in a public product it is surprising: it
   runs a site's scripts and trackers in the app's persistent web store. Ask the first time per site ("Digby can
   open this page out of sight and catch the video, like you would by pressing play. Allow for rumble.com?") and keep a
   per-site setting.
7. **Build tooling:** no Xcode blocks notarisation-friendly signing, the Safari extension, App Intents metadata
   extraction, String Catalog compilation and XCTest/XCUITest. Command-line-only was a reasonable start; it is now the
   main constraint on quality.

### C.7 Opportunities for differentiation (nobody does these well)
* "Plays on this Mac" as the default promise.
* Verified downloads, shown as a small seal: "Checked: picture 1080p H.264, sound AAC, 12:34, 587 MB".
* Recovery before failure, with a visible "What Digby tried" list (already built — make it a signature moment).
* A public, honest **site status page** generated from the canary runs ("YouTube: working, engine 2026.11.04").
* On-device translation of subtitles (if verified live).
* The Digby family: "Download, then make it smaller" as one action, once the Compressor URL scheme exists.

---

## D. Gold-standard product specification

Principles stay as in `PRODUCT_SPEC.md` (never claim success that didn't happen, never compromise silently, simple by
default, native, self-maintaining). Add two:
* **Decisions are preferences, not gates.** Ask once; apply forever; let people change any item afterwards.
* **Trust is a feature.** Signed, notarised, self-updating, no telemetry, no ads, no limits, said plainly.

### D.1 Essential (a competitive product must have these)
| # | Feature | Specification |
|---|---|---|
| E1 | Developer ID + notarisation | Hardened runtime; managed engines stay outside the bundle (they are signed by their publishers and verified as today). DMG notarised and stapled. |
| E2 | App updates | Sparkle 2 with EdDSA signatures; appcast on GitHub Releases; "Install on quit"; never during a download (same rule as engines). |
| E3 | Quick download | Settings → "When I paste a link: Download right away with my usual choices / Show me the choices first". Default: right away. ⌘V in the window, the hot-key, Services, Share and the browser button all follow it. Each item shows its plan sentence and "Change…" until it starts; changing after it starts offers "Download again with these choices". |
| E4 | Default quality rule | "Best that plays on this Mac" (resolution capped by what decodes in hardware here; H.264/HEVC/AV1 per chip). Alternatives in the Inspector: "Highest available", "Smaller files (1080p)", "Audio only". |
| E5 | Crash-safe queue | Queue rows in SQLite; written on each change; on launch, running items resume automatically (partial data kept), waiting items stay waiting. No "Continue/Discard" prompt unless the destination disappeared. |
| E6 | Duplicate check | Before downloading: same video ID in History with the file still present → "You downloaded this on 3 Nov (1080p). Open it / Download again / Download a different version". |
| E7 | Live streams | Detect `is_live`/`is_upcoming`/`was_live`; offer "Record from now", "From the start" (where the site allows), "Download when it ends" (Watching handles the wait); stop button that finalises a playable file. |
| E8 | Safari extension | Toolbar button + context menu "Download with Digby", same `digby-video://` contract; plus Firefox. |
| E9 | Accessibility gate | VoiceOver labels and grouped controls, text styles, Increase Contrast, Differentiate Without Colour, full keyboard navigation, announcements for completion and failure. Manual audit before every release. |
| E10 | Localisation-ready | String Catalog; all user-visible text and explanations extracted; first languages chosen by audience (suggest: Simplified Chinese, Spanish, German, French, Japanese, Portuguese). |
| E11 | Universal binary | arm64 + x86_64 (needs Xcode build or `lipo` of two SwiftPM builds). Hardware-decode checks already exist; extend for Intel (no AV1 decode). |

### D.2 Important (substantially better)
| # | Feature | Specification |
|---|---|---|
| I1 | Unified Destinations | Replace Projects + Save Into + folder sorting with Destinations (name, symbol, folder, optional sort rule, optional default choices). Sidebar lists them. |
| I2 | Inspector | Trailing inspector for the selected item: plan, what the site offered, verification seal, log, actions. Replaces the details sheet and inline expansion. |
| I3 | SponsorBlock | Off by default; when on: "Mark as chapters" (default) / "Remove from the file" (re-cut, stated). Shows how many seconds were marked. |
| I4 | Per-download log | Every item keeps its redacted log; "Copy Report" uses it. |
| I5 | Network panel | System proxy (default) / custom HTTP/SOCKS / per-site rule; "Test connection to this site" button that shows which route worked. |
| I6 | Services, Share menu, Shortcuts | "Download with Digby" Service for selected text; Share extension; App Intents: *Download URL*, *Get Video Info*, *Add to Watching*, returning the file. |
| I7 | Background watching | Login-item helper checks Watching on schedule with the app closed, respecting Low Power Mode and metered networks. |
| I8 | Undo and Clear | Undo for remove/clear/cancel; "Clear Finished" in the Downloaded view. |
| I9 | Onboarding | One sheet on first run while engines install: paste a link now (it queues), the three entry points, the default quality rule with one alternative. No more. |
| I10 | iCloud history sync (optional) | Like Downie; history only, never cookies. |

### D.3 Advanced (professional-grade)
* **For Experts** panel: custom yt-dlp arguments (allow-listed), output template as text, per-site format overrides,
  `--sleep-*` politeness, fragment concurrency, impersonation choice, cookies file import.
* **Split by chapter** for audio, with metadata and artwork per track.
* **Loudness normalisation** (EBU R128) as an explained conversion.
* **HDR → SDR tone-mapping** as an explained conversion for HDR-only sources.
* **Exports:** History as CSV/JSON; Watching list import/export (OPML-like JSON).
* **CLI parity**: `digby-dl` shares the queue, profiles and destinations; documented in the help.
* **Command-line and AppleScript automation** via App Intents (AppleScript comes via Shortcuts).

### D.4 Differentiators (what could make it the definitive downloader)
1. **"Plays on this Mac" promise** made visible: every item states "Plays in QuickTime and Photos" or why not.
2. **Verified seal** on every finished item, with what was checked.
3. **"What Digby tried"** timeline on every recovered or failed item: the most trustworthy error UX in the category.
4. **Public site-status page** fed by canary downloads against the current and nightly engines; the app shows a quiet
   "YouTube is having problems for everyone right now — Digby will retry automatically" banner when the canary fails.
5. **Find the Video on the Page** taken further: a picker overlay that highlights each playing video on the page with
   its label ("This one: 1080p, 12 min"), so users choose by pointing, not by reading a list.
6. **One-step Download and Compress** through the Compressor (needs its URL scheme, with permission).
7. **On-device subtitle translation**, once verified live.
8. **No limits, no ads, no telemetry, no account**, stated plainly in the app and on the site.

### D.5 What *not* to build
* AI vocal removal and similar 4KVD extras: off-mission.
* A built-in media player or library (Stacher Premium's direction): Finder, Quick Look, Photos and Music already do this.
* Any CAPTCHA solving, DRM handling or paywall bypass (already excluded; keep it that way).
* More modes or toggles in Settings without a clear default.

---

## E. Prioritised roadmap

Each stage ends with a verified, signed build. Effort: S = days, M = 1–2 weeks, L = 3+ weeks (one developer).

### Stage 0 — Decide and stabilise (S–M) · *prerequisite for everything*
1. Make the five decisions in §F.
2. **Feature freeze.** Verify live everything marked ◐: catcher stops playback, Google sign-in window, quit and
   relaunch mid-download, hot-key, Watching against a real channel, overnight wait (with a short test window),
   translation, Quick Look, drag out, browser extension click-through.
3. Fix what that turns up. Update `ARCHITECTURE.md` to match the code.

### Stage 1 — Trust and distribution (M) · *needs: Developer account, Xcode*
E1 notarisation · E2 Sparkle · E11 universal build · move the build to an Xcode project or `xcodebuild` on the SwiftPM
package (keep SwiftPM targets as the source of truth).

### Stage 2 — Core refactor (M) · *needs: nothing; unblocks 3, 5, 6*
Extract `DownloadQueue` actor, `RecoveryCoordinator`, `DraftStore`, `WatchService` into `DigbyDownloadCore`; queue
in SQLite (E5); per-download logs (I4); view-model tests.

### Stage 3 — The default flow (M) · *needs: Stage 2*
E3 quick download · E4 default quality rule · plan sentence + "Change…" · Inspector (I2) · remove tabs/list toggle ·
Destinations (I1) · duplicate check (E6) · undo/clear (I8) · onboarding during engine install (I9). **This is the
stage users will notice most.**

### Stage 4 — Accessibility and localisation (M) · *runs alongside Stage 3; must finish before public release*
E9 and E10: String Catalog, text styles, grouped controls, rotors, announcements, contrast; manual VoiceOver audit;
first two translations.

### Stage 5 — Reach (M) · *needs: Stage 1*
E8 Safari + Firefox extensions · I6 Services, Share, Shortcuts · I7 background Watching helper.

### Stage 6 — Category coverage (M)
E7 live streams · I3 SponsorBlock · I5 network panel · chapter split · politeness on 429.

### Stage 7 — Differentiators (L, ongoing)
Canary runs + public site-status page · "What Digby tried" timeline polish · pointing-based page picker · Compressor
hand-off with presets · iCloud history sync · For Experts panel.

**First public release:** after Stages 0–4. Stages 5–7 can ship as updates, which Stage 1 makes possible.

---

## F. Final assessment

**How far away?** The core is genuinely ahead of the category on correctness, honesty and recovery; that work is
hard to copy, and it is done. The product around it isn't yet competitive with Downie on the three things people
actually judge a downloader by in the first five minutes: *Can I install it without fear? Does ⌘V just work? Will it
still work next month?* Today the answers are "with a scary detour", "not without a decision page", and "the engine
will, the app won't". All three are fixable in Stages 0–3, roughly six to eight weeks of focused work, *if* new
features stop for that time.

**Biggest opportunities**
1. Be the downloader that **never gives you a file you can't play** and **always tells you what it did**.
2. Be the one that **is still working tomorrow** — and proves it with a public status page.
3. Be the only free one that **feels like Apple made it**: notarised, accessible, localised, no ads, no limits.

**Decisions needed now**
| # | Decision | Options | Recommendation |
|---|---|---|---|
| 1 | Apple Developer Program ($99/yr) + Xcode | Pay / stay unsigned | **Pay.** Notarisation, Sparkle, Safari extension and App Intents all depend on it. Without it, the gold standard is not reachable on the Mac. |
| 2 | Default paste behaviour | Download right away / show choices | **Right away**, with a one-line plan and "Change…". Choices page stays one click away. |
| 3 | Default quality rule | Plays on this Mac / Highest available | **Plays on this Mac.** Matches the brand promise; "Highest" one click away. |
| 4 | Scope control | Freeze and verify / keep adding | **Freeze**, verify, merge Projects + Save Into + folder sorting into Destinations, drop tabs/list toggle. |
| 5 | Hidden page catcher | On silently / ask once per site / off | **Ask once per site.** Same capability, no surprise. |
| 6 | Intel support | Universal / Apple Silicon only | Universal, if Xcode is adopted (cheap then); otherwise state "Apple silicon" on the site. |
| 7 | Release language(s) | English only / localised from 1.0 | Extract strings now; ship English + the user's priority language(s) at 1.0. |
| 8 | Distribution channel | Direct (DMG + Sparkle) / Mac App Store | **Direct.** The App Store sandbox and review are hostile to bundled downloaders and runtime engine installs. |

**Your answers (2026-11-15)**
* **Agreed and built — #3 (Round 8):** the default is now "best that plays on this Mac". Today "Best" takes the highest resolution first
  and only then prefers a playable format, warning when none plays (`Selection.swift`, the `.best` and `.automatic`
  branches). The change: when "prefer playable" is on and the file type is MP4/MOV, "Best" means the highest
  resolution that has a format this Mac plays; higher ones stay one click away, named in the note.
* **Skipped:** #1 (developer account / Xcode), #2 (⌘V downloads straight away), #6 (Intel), #7 (languages),
  #8 (distribution channel). Stages 1 and 5 of the roadmap depend on #1 and are parked with it.
* **Open:** #4 — you've tested most features by hand; the ones still listed as unverified in
  `IMPLEMENTATION_STATUS.md` need confirming or ticking off.
* **Agreed and built — #5:** ask once per site before playing a page out of sight (Round 7 in `IMPLEMENTATION_STATUS.md`).

---

## 7. Sources

* Downie — https://software.charliemonroe.net/downie/
* 4K Video Downloader Plus — https://www.4kdownload.com/products/videodownloader-42
* PullTube — https://mymixapps.com/pulltube
* Parabolic — https://github.com/NickvisionApps/Parabolic
* Open Video Downloader — https://github.com/jely2002/youtube-dl-gui
* MacYTDL — https://github.com/section83/MacYTDL
* Seal — https://github.com/JunkFood02/Seal
* JDownloader 2 download page — https://jdownloader.org/jdownloader2
* Stacher coverage — https://alternativeto.net/software/stacher/about/ · https://softorino.com/blog/best-yt-dlp-gui-alternatives
* Downie review — https://thesweetbits.com/tools/downie-video-downloader/ · Downie vs PullTube — https://thesweetbits.com/pulltube-vs-downie/
* Setapp roundup — https://setapp.com/app-reviews/best-youtube-downloaders
* 4KVD+ complaints — https://techissuestoday.com/4k-video-downloader-plus-not-working-heres-whats-going-on · https://www.trustpilot.com/review/www.4kdownload.com · https://talk.tidbits.com/t/4k-video-downloader-plus-26-2/33921 · https://www.producthunt.com/products/4k-video-downloader/reviews
* yt-dlp PO tokens / JS runtime — https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide · https://gigazine.net/gsc_news/en/20250925-yt-dlp-deno-javascript-runtime
