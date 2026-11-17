# Digby Video Downloader — Architecture

Status: Phases 1–3 implemented (2026-11-14). Sections below describe the built system; §6–7 details are in the code.

## 1. Platform decisions

| Decision | Choice | Why |
|---|---|---|
| Language / UI | Swift 6, SwiftUI + Observation (`@Observable`), AppKit where SwiftUI falls short (menu bar, hot key, pasteboard, `NSWorkspace`) | Same stack as Digby Video Compressor; native look and behaviour; no web view. |
| Minimum macOS | **macOS 14 Sonoma** | Matches the Compressor's source requirement (`Package.swift` → `.macOS(.v14)`), needed for Observation and modern SwiftUI. The Compressor *ships* with `LSMinimumSystemVersion 26.0` only because it bundles Homebrew FFmpeg dylibs built for macOS 26. The Downloader avoids that by using self-contained, application-managed tools, so it can genuinely run on 14+. Each managed tool's own `minos` is checked at install time (`vtool`-equivalent Mach-O read). |
| Architecture | Apple Silicon (arm64) app binary; arm64 managed tools where offered (yt-dlp's macOS build is universal) | Target is the M1 family. A universal app binary needs Xcode's build system; this Mac has Command Line Tools only. Revisit if Intel support is ever wanted. |
| Build | SwiftPM, `--scratch-path` outside iCloud `~/Documents` (same quirk as the Compressor); `Scripts/build_app.sh` assembles the `.app` and DMG | Proven in the Compressor on this machine. |
| Tests | `digby-dl-tests` executable target (pure logic) + fixture-driven integration suite | Command Line Tools ship no XCTest; the Compressor's approach works. |
| Persistence | SQLite via the system `SQLite3` module, thin in-house wrapper, schema migrations | No third-party dependency; durable, queryable history. Settings in `UserDefaults` (versioned keys). |
| Engines | yt-dlp (extraction + download), FFmpeg/FFprobe (merge, remux, convert, inspect), Deno (yt-dlp's JavaScript challenge solver) — all **separate processes** launched with argument arrays | Crash isolation, licence separation (app never links GPL code), replaceable engine. |

## 2. Module map

SwiftPM targets (each a folder under `Sources/`):

```
DigbyDownloaderApp  (SwiftUI app: windows, menu bar, commands; App/AppModel holds drafts, the queue and scheduler,
   │                  the recovery chain and Watching; Views/PageCatcher is "Find the Video on the Page")
   │  depends on
   ├── DigbyDesign        DesignSystem: tokens, Landfall motif, cards, pills, buttons, motion
   └── DigbyDownloadCore  everything below, UI-free, testable
          Model/          MediaInfo, MediaFormat, MediaCollection, Profiles
          Extraction/     YtDlpEngine (analysis, sign-in retries, live check) · YtDlpDecoder · SignIn · CaughtStream
          Formats/        Families (codecs, PlaybackEnvironment) · Catalogue · Selection (FormatSelector: choices → plan)
          Download/       Downloader (yt-dlp fetch, progress, pause/resume) · PostProcessor (FFmpeg copy/convert, FFprobe verify)
          Dependencies/   Tools · DependencyManager (actor: verified install, atomic switch, rollback) · OpenPGP
          Diagnostics/    ErrorClassifier · Recovery (RecoveryPolicy, EngineRecovery) · DiagnosticAdvisor (protocol only)
          Explain/        Explanations (plain-English summaries, pros and cons for every choice)
          Library/        HistoryStore (SQLite) · DownloadDetails · FileNamer (templates, NameParts, FolderSorting)
          Support/        ProcessRunner · Paths · Redactor · Log · SystemNetwork · PageStatus · SiteKey · Subtitles · Format
digby-dl            (CLI front end to the core; used by integration tests)
digby-dl-tests      (unit tests)
```

The brief's recommended module names map onto these folders; they are folders inside one core target rather than
twenty SwiftPM targets, which keeps build times and access-control friction down without losing the boundaries.

## 3. The engine boundary (UI never sees yt-dlp)

```swift
protocol MediaExtractor {          // analyse a URL
    func analyse(_ url: URL, options: ExtractionOptions) async throws -> ExtractionResult   // .single(MediaInfo) | .collection(Playlist)
}
protocol DownloadEngine {          // execute a resolved plan
    func download(_ plan: DownloadPlan, to dir: URL, events: (DownloadEvent) -> Void) async throws -> DownloadOutcome
}
```

* `MediaInfo`/`MediaFormat` are **Digby's own types**, decoded from `yt-dlp -J` JSON by `YtDlpJSONDecoder`. Nothing
  outside `Extraction/` and `Download/YtDlp*` knows a yt-dlp field name or flag.
* Progress comes from `--newline --progress-template` emitting one JSON object per line (prefixed with a sentinel so
  stray output can't be mistaken for it). Final paths come from `--print after_move:` as JSON. No scraping of
  human-readable output except as a last-resort diagnostic signal.
* Always passed: `--ignore-config --no-update --no-colors --js-runtimes deno:<managed path>
  --ffmpeg-location <managed dir>`, `--` before the URL. No shell, ever: `Process` with an argument array.
* A second engine (e.g. a direct HLS/HTTP fetcher, or a future native extractor) plugs in by implementing the protocols.

## 4. Format selection (the core differentiator)

**Digby chooses the streams, not yt-dlp's sort.** Analysis yields every format; Digby picks exact format IDs and passes
`-f <videoID>+<audioID>` (or one ID). That makes selection deterministic, testable from fixtures, and means a lower
resolution can never be substituted silently.

1. `FormatAnalyzer` normalises raw formats into a **catalogue**:
   * video streams grouped by **resolution tier** (short side → 4320/2160/1440/1080/720/480/360/240/144; portrait and
     odd sizes handled by short side, the exact dimensions kept), then by **codec family** (AVC, HEVC, AV1, VP9, other),
     with fps, HDR (from `dynamic_range`), bit depth, bitrate, size (`filesize` = exact, `filesize_approx`/bitrate×duration = estimated);
   * audio streams grouped by **language** (original vs dubbed from `language_preference` / format notes; never inferred
     from the title), then codec and bitrate, channels;
   * muxed formats recognised as such; storyboards/images dropped; DRM-flagged formats excluded and reported.
2. `FormatSelector` turns `Choices` (type, tier, codec, container, language, audio quality, subtitles) into a
   `DownloadPlan`:
   * video: exact tier → requested codec (or best for the container) → higher fps unless capped → SDR/HDR per preference → higher bitrate;
   * audio: preferred language → fallback language → original track → container-compatible codec (AAC for MP4/MOV,
     Opus for WebM, anything for MKV) → bitrate;
   * container/codec compatibility table decides **copy**, **remux**, or **transcode**; transcoding is never chosen
     silently — the plan carries a `Deviation` list ("Opus audio will be converted to AAC for MP4 — choose MKV to keep it untouched").
   * if the request cannot be met exactly, the plan is `.unsatisfiable(reasons, alternatives)` and the UI offers the alternatives.
3. Every user-facing option is computed from the catalogue, so unavailable resolutions/codecs/languages never appear.

## 5. Queue and jobs

* `DownloadJob` is a value snapshot: URL, resolved `DownloadPlan`, destination rule, profile name. Changing defaults never
  touches queued jobs.
* The queue and its scheduler live in the app's `AppModel` (main actor). Unfinished downloads are written to
  `Unfinished downloads.json` every few seconds and on quit, so a crash, force quit or restart loses nothing; on the next
  launch they're offered to continue (partial data kept). Planned: move the queue into the core as an actor.
  States: waiting → analysing → downloading → post-processing → verifying → done | failed(diagnosis) | cancelled | paused.
* Scheduler: global concurrency 2 (configurable 1–6), per-site 1–2, polite spacing for playlists.
* Pause = stop the process, keep yt-dlp's `.part` files, resume with `--continue`. Cancel removes partials.
* Output is written in a per-job working folder, verified with FFprobe (duration, streams, codecs match the plan), then
  moved atomically to the final, collision-free name. A job is "done" only after that check.

## 6. Dependency manager

Tools live in `~/Library/Application Support/Digby Video Downloader/Tools/<tool>/<version>/`, with an `active` pointer
(symlink swapped atomically) and the previous version kept for rollback.

| Tool | Official source | Artefact | Verification |
|---|---|---|---|
| yt-dlp | github.com/yt-dlp/yt-dlp releases (stable), yt-dlp-nightly-builds, yt-dlp-master-builds | `yt-dlp_macos.zip` (unpacked PyInstaller build: fast start-up; we manage updates, so its missing self-update is irrelevant) | `SHA2-256SUMS` + its OpenPGP signature `SHA2-256SUMS.sig` against yt-dlp's public key **pinned in the app** |
| Deno | github.com/denoland/deno releases | `deno-aarch64-apple-darwin.zip` (`deno`, not `denort`) | `.sha256sum` from the release + Developer ID code-signature check with pinned Team ID |
| FFmpeg / FFprobe | ffmpeg.martin-riedl.de (static macOS arm64 builds) | `ffmpeg.zip`, `ffprobe.zip` | `.sha256` + Developer ID code-signature check with pinned Team ID |

Install flow: fetch release metadata → download to temp → verify → unpack → strip nothing, quarantine not applied (we
download it ourselves) → run a **smoke test** (`--version`; yt-dlp also runs an offline extraction of a bundled fixture)
→ swap `active` → record in update history. Failure at any step leaves the previous version active.
Checks: at launch at most once per day (stable) / 6 h (nightly), plus on-demand after an "outdated extractor" diagnosis.

## 7. Diagnostics and recovery

`ErrorClassifier` maps yt-dlp's error lines, exit codes and our own checks to a `Failure` enum (outdated extractor,
login required, unavailable, private, geo-restricted, network, rate-limited (HTTP 429 / "Sign in to confirm"),
unsupported format, missing dependency, JS runtime failure, permissions, disk space, DRM). Each case has: user-facing
explanation, `isRetryable`, backoff, and a recovery action (update engine → re-analyse → retry once; never more than
three automatic attempts per job; never re-download completed files). Fixtures of real error output drive the tests.
Diagnostic bundles are **redacted** (cookies, tokens, query strings of private URLs, home path) before anything is shown,
copied or — in a future opt-in AI helper — sent anywhere.

## 8. Digby Video Compressor hand-off (no change to the Compressor needed)

Inspection of the Compressor (`Sources/DigbyApp/App/DigbyApp.swift`, `Scripts/build_app.sh`):
* It declares `CFBundleDocumentTypes` for movie/MP4/QuickTime/MKV/WebM (role Viewer) and implements
  `application(_:open:)` → `AppModel.add(urls:)`.
* Bundle id `app.digbyvideo.compressor`.

So "Compress with Digby" = `NSWorkspace.urlForApplication(withBundleIdentifier:)` →
`NSWorkspace.shared.open([file], withApplicationAt:, configuration:)`. It launches the Compressor if needed and adds the
file to its queue; the original download is untouched (the Compressor never modifies sources unless the user picks
"replace"). If the Compressor isn't installed the button becomes "Get Digby Video Compressor" (opens its website).
Proposed *future* Compressor change (not to be made without permission): a `digby-compressor://add?path=…&preset=…`
URL scheme so the Downloader can pass a preset (needed for the "Small File" profile's automatic compression).

Shared conventions: the Downloader writes the standard `com.apple.metadata:kMDItemWhereFroms` attribute (source URL —
Finder's "Where from") and its own `app.digbyvideo.downloader` extended attribute (JSON: source site, format summary).

## 9. As built in Phase 3 (differences from the proposal)
* Targets: `DigbyDesign`, `DigbyDownloadCore` (folders Model, Formats, Explain, Extraction, Download, Dependencies,
  Diagnostics, Library, Support), `DigbyDownloaderApp`, `digby-dl` (CLI), `digby-dl-tests`.
* `ProcessRunner` uses `posix_spawn` with a new process group per child, so cancel (SIGTERM → SIGKILL) reaches FFmpeg
  started by yt-dlp; a registry stops every child when the app quits.
* yt-dlp is launched by its real path (the unpacked build finds its libraries beside itself); `--ffmpeg-location` points
  at `Tools/bin`, a folder of links to the active FFmpeg and FFprobe.
* Progress: `--progress-template "download:CDLP %(progress)j"`; final path: `--print "after_move:CDLF %(filepath)j"`.
* `FormatInspector` fills codecs a site doesn't report by reading stream headers with FFprobe (`-http_proxy`, `-ca_file`
  from `SystemNetwork`: the Mac's proxy and its trusted certificates exported once per launch).
* The selector downloads audio-only from the smallest combined file when a site has no separate sound stream (stated).
