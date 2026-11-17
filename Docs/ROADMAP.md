# Roadmap and implementation phases

Each phase ends with a working, tested build and an updated IMPLEMENTATION_STATUS.md. Nothing is reported as working
until it has been exercised for real.

All seven phases are complete (2026-11-14). Next steps after 1.0 are below the table.

| Phase | Deliverable | Exit test |
|---|---|---|
| 1 Research & audit | Docs in this folder | Your approval of the plan |
| 2 Design system & UI shell | `DigbyDesign` target, icon script, main window with every state rendered from mock data, menu bar extra, settings skeleton | Offscreen renders of every state, light + dark (the Compressor's `RENDER_DETAIL` technique, since this Mac has no Screen Recording permission for me) |
| 3 Core engine | Dependency install + verification, yt-dlp analysis → catalogue → plan → download → merge → FFprobe verify | Fixture unit tests; real end-to-end download of public test media (e.g. Blender open movies on YouTube/Vimeo, Internet Archive) |
| 4 Advanced | Playlists, batch, queue persistence, subtitles, languages, profiles, history, naming, folders | Queue survives a forced quit mid-download; history search; playlist partial selection |
| 5 Maintenance | Update channels, scheduled checks, rollback, error classifier, automatic recovery, diagnostic export | Simulated broken engine → recovery; rollback restores previous version |
| 6 Digby integration | Compress with Digby | Downloaded file opens in the installed Compressor; original untouched |
| 7 Polish & release | Accessibility pass, performance, security review, DMG, notices | Fresh-user install on a clean account |

## Later (designed for, not built in 1.0)
* Opt-in AI troubleshooting: `DiagnosticAdvisor` protocol fed only redacted bundles; suggestions only, never executes code
  or swaps binaries outside the normal verified update path.
* Compressor URL scheme with presets → automatic "download then compress" (needs a small Compressor change, with permission).
* Browser extension (needs Xcode for a Safari Web Extension), watch folders, scheduling, media library, Digby workspace.
* Additional engines behind `MediaExtractor` / `DownloadEngine`.

## After 1.0 (suggested order)
1. Publish: public repository + release + family website (waiting for your go-ahead).
2. A neutral web address for the Digby family (the current GitHub Pages address contains a personal account name).
3. Confirm Rumble/Vimeo through Find the Video on the Page (any-site sign-in is built; Cloudflare blocks automatic reads here).
4. Developer ID signing and notarisation (needs a paid Apple Developer account) to remove the first-launch warning.
5. Compressor URL scheme with presets → one-click "download then compress".
