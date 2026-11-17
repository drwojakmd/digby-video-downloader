# Digby Video Downloader — Product Specification

Status: **Phase 1 draft**. Source: the project brief (2026-11-14) plus decisions recorded below.

## Promise
Paste a link, see exactly what you'll get, download it at the quality you chose — or be told clearly why not.

## Principles (from the brief, in priority order when they conflict)
1. Never claim success that didn't happen (a download is "done" only after FFprobe verifies it).
2. Never silently compromise requested quality (no hidden downgrade, no hidden re-encode).
3. Easy for beginners; powerful underneath (Simple by default, Advanced on request).
4. Native, calm, premium macOS design in the Digby family.
5. Self-maintaining engines; no Terminal, Homebrew or Python ever needed.
6. Modular, replaceable engine; tested from the start.

## Primary flow
Paste URL → Analyse (preview card appears) → choose (type · resolution · codec · container · language · subtitles,
with live size estimate and plan sentence) → Download → Done (Reveal · Open · Compress with Digby).

## Scope of version 1.0
* Single URLs, multiple URLs (batch paste, duplicates detected by canonical URL / video id), playlists and channels
  (expandable groups, select/exclude items, retry failed).
* Video + Audio / Video Only / Audio Only; resolution tiers present in the source; codec AVC/HEVC/AV1/VP9 where present;
  MP4 / MKV / WebM / MOV with copy-first logic; audio languages (original vs dubbed, preferred + fallback); audio output
  Original / M4A / MP3 / FLAC / WAV / Opus (conversion clearly labelled); subtitles none / embedded / separate files,
  chosen or all languages, human vs automatic, SRT/VTT.
* Advanced Mode: searchable, sortable format table; pick exact streams.
* Queue: concurrency (global + per site), pause/resume, cancel, retry, reorder, clear completed, persists across launches.
* Profiles: Maximum Quality, Universal Compatibility, Archive, Audio Archive, Small File; user-editable.
* File naming templates, sanitising, collision handling (never overwrite), per-type destination folders.
* History (SQLite): search, filter, re-download, open, reveal, remove record (file kept unless explicitly asked).
* Engine management: install, verify, update (Stable default / Nightly / Master), rollback, history.
* Diagnosis: classified failures, plain-language explanations, safe automatic recovery, redacted diagnostic export.
* macOS: drag-and-drop, menu bar extra, global shortcut, opt-in clipboard detection (offers, never auto-downloads unless
  you configure it), notifications, Services/Finder reveal, full keyboard control, VoiceOver, light/dark, Reduce Motion.
* Compress with Digby hand-off.

## Explicitly out of scope
DRM circumvention, paywall/access-control bypass, credential harvesting. Sign-in only through the user's own browser
session (`--cookies-from-browser`) or a cookies file the user supplies, used locally and never logged.
Optional AI troubleshooting: architecture hook only in 1.0 (see ROADMAP).

## Open product decisions
See IMPLEMENTATION_STATUS.md → "Decisions needed".
