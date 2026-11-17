# Security review (Phase 7, 2026-11-14)

| Area | How it's handled | Checked by |
|---|---|---|
| Running tools | Only four programs are ever launched: the managed yt-dlp, FFmpeg, FFprobe (and Deno via yt-dlp), plus `/usr/bin/ditto` to unpack. Always `posix_spawn` with an argument array; never a shell. | grep audit: no `/bin/sh`, `-c`, `system()`, `popen`, AppleScript |
| Links as arguments | Every link goes after `--`, so it can't be read as an option. FFprobe only inspects `http(s)` stream addresses (never `file:` or other protocols a site might send). | Code review |
| Engine authenticity | yt-dlp: OpenPGP signature on `SHA2-256SUMS` verified against the pinned key (fingerprint `AC0C BBE6 … 3B5A 7581`); Deno/FFmpeg: SHA-256 from the release + Apple Developer ID with pinned team. Nothing is run before it passes. | Unit tests with real signed files; tampered data and corrupted signatures rejected |
| Engine install | Staged in a private folder, test-run, switched in with an atomic link rename; previous version kept; failures leave the old version active. | Real install, channel switch, rollback |
| Downloaded files | Written to a hidden work folder inside the destination, verified with FFprobe, then renamed; never overwrites (adds a number). Site-supplied text (titles, subtitle language codes) is sanitised before it touches a file name, so it can't form a path. | Unit tests (sanitising, collisions); fix for subtitle language codes |
| Sign-ins | Browser sign-ins are read fresh per run and never stored. In-Digby sign-ins are stored as a cookie file containing only `youtube.com` and Google account cookies, mode 600, in a mode-700 folder. Sent only to that site. | Unit tests (domain filter incl. look-alikes, permissions) |
| Logs and reports | Home folder, query strings (signatures, tokens) and cookie values are removed before anything is written; reports name the site, never the full link. | Unit tests on the redactor and report |
| Network | Only the site being downloaded from, GitHub (engine releases) and the FFmpeg build server. Uses the Mac's proxy settings. No telemetry. | Code review |
| Optional AI | `DiagnosticAdvisor` may only receive a redacted report and return text; it can't run code or change engines. Not enabled. | Design (Diagnostics/DiagnosticAdvisor.swift) |

Known residual risks: the app is ad-hoc signed (not notarised); a compromised publisher account could publish a
validly signed malicious engine (mitigated by pinning keys/teams, test runs and rollback, as with any updater).

## Browser button and `digby-video://` links (1.1)
* The app registers `digby-video://download?url=<page>`. It only fills in the link and reads the page, exactly as if
  pasted: it never starts a download, and only `http`/`https` page addresses are accepted.
* The Chrome-family extension asks only for `contextMenus` and `activeTab`, keeps nothing, and talks to nothing but the
  app (through that address). The bookmarklet does the same from any browser.

## Subtitle translation (1.1)
* Uses macOS's on-device Translation framework. Subtitle text never leaves the Mac; language packs come from Apple
  through the system's own prompt.
