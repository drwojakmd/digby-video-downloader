# Third-Party Notices — licensing analysis (Phase 1)

The app itself links only Apple frameworks and the system SQLite. Engines run as separate processes and are
**downloaded by the app from their official sources on first run**, not shipped inside the DMG. This file is bundled
in the app (Contents/Resources/Licenses) and summarised in About → Acknowledgements.

| Component | Version checked 2026-11-14 | Licence | Obligations / notes |
|---|---|---|---|
| yt-dlp source | 2026.10.26 | The Unlicense (public domain dedication) | None for the source itself. |
| yt-dlp `yt-dlp_macos` / `yt-dlp_macos.zip` (PyInstaller builds) | 2026.10.26 | **GPLv3+ as a combined work** (bundles CPython and GPL components) per yt-dlp's README; the zipimport build also contains ISC/MIT code (meriyah, astring) | Separate process → the app is not a derivative work. If we ever *ship* the binary inside the DMG we must provide/point to corresponding source and the GPL text. Downloading from upstream at runtime avoids redistribution. |
| yt-dlp-ejs (bundled inside the yt-dlp builds) | — | Unlicense / bundles MIT, ISC parts | Covered by the yt-dlp build's notices. |
| Deno | 2.9.8 | MIT | Downloaded by the app, not redistributed. Signed: Developer ID Deno Land Inc. (2H4KBF436B). |
| FFmpeg / FFprobe (martin-riedl.de static builds) | 9.0.2 | **GPLv3 or later** — confirmed: built with `--enable-gpl --enable-version3` (x264, x265, SVT-AV1, libopus, LAME…); `ffmpeg -L` prints GPLv3+ | Separate process, downloaded by the app from the publisher, not redistributed. Signed: Developer ID Martin Riedl (KU3N25YGLU). |
| SF Pro | system | Apple | Used via the system only, never bundled. |

Each engine's own licence text ships inside the engine as downloaded (e.g. `ffmpeg -L`, yt-dlp's `_internal` folder).
