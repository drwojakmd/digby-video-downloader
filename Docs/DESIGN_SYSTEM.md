# Digby Video Downloader — Design System

Status: **Phase 1 proposal**. Final values are fixed in Phase 2, in code (`Sources/DigbyDesign`), which becomes the source of truth.

## 1. Audit of Digby Video Compressor (what is actually there)

Read from `Docs/Brand/BRAND.md`, `Sources/DigbyApp/Views/Components.swift`, `DropZoneView.swift`. (App icons have since moved to the Digby "Chevron" pair: masters in `../../brand/icons/`, rendered by `../../design/icons/install.sh`.)

| Element | Compressor reality |
|---|---|
| Idea | "Convergence": six digby streaks crossing a dawn sky and converging on one bright point. Many → one: weight becomes something small and luminous. **No cloud silhouettes** (that reads as cloud storage). |
| Colour | Sky accent `#3A6AAE` / dark `#8FB6E8`; Dawn `#D98E62` / `#F0B28C` for *arrival only*; Altitude `#14294D` (midnight navy); Haze `#BFD3EA`; Dawn fixed `#F2C2A0`. Sky gradient Altitude → `#4D7DB8` → Haze → Dawn. Semantic colours are the system's; Dawn is never a warning. |
| Type | SF Pro (system), Dynamic Type, tabular figures; display text in SF Pro Light (28 pt drop-zone headline, kerning −0.3). Marketing: Hanken Grotesk Light. *(Note: the brief mentions Manrope, but the Compressor's code and brand doc use SF Pro + Hanken Grotesk. The Downloader follows the actual product.)* |
| Components | `Card` (14 pt continuous radius, 0.5 pt separator stroke, 4 % shadow), `SectionLabel` (11 pt semibold uppercase), `Chip`, `PillButton` (capsule, accent fill when selected), `ProminentButtonStyle` (10 pt radius, accent gradient, soft accent shadow), `StatTile`, `InfoRow`. |
| Motion | Streaks drift when idle, settle on drag-over, draw toward the point as progress (`ConvergenceProgress`), Dawn point on completion. All honour Reduce Motion. |
| Window | Single `Window` scene, unified toolbar with title, `NavigationSplitView` (sidebar 240–340), detail on window background; empty state = sky panel (190 pt tall, 22 pt radius) + dashed drop target. |
| Icon | Drawn by a Swift script on the macOS grid (824 pt body, 185 pt corners), simplified 3-streak version at ≤ 32 px. |
| Voice | Plain, calm, precise; explains what will happen ("Each original goes to the Trash only after…"). |

## 2. Adaptation: "Landfall"

The Compressor's streaks run **horizontally** and converge on a point (compression). The Downloader's streaks
**descend**: they come from high altitude and arrive at one point on the horizon — something from far away, brought
down to you. Same sky, same materials, a different gesture. The two icons side by side read as a family
(sky + streaks + dawn point) yet are instantly distinguishable (horizontal vs falling).

| Token | Value | Use |
|---|---|---|
| Sky (accent) | shared with Compressor | buttons, selection, progress |
| Dawn | shared | arrival only: a finished download, the landing point |
| Altitude, Haze, Dawn fixed | shared | icon and empty-state sky |
| **Dusk Navy** (new, Downloader only) | ≈ `#0F1F3D` | the deeper top of the Downloader's sky, so its empty state feels "higher" than the Compressor's |
| Radii | Card 14, prominent button 10, panel 22, outer drop zone 26 | shared |
| Spacing | 4-pt grid; card padding 18; section gap 14 | shared |

### Tagline
**Anything you find. Yours to keep.** (chosen by you, 2026-11-14). The Downloader's counterpart to the Compressor's
"Less weight. Same picture.": two short sentences, the first about where media comes from, the second about the promise.
Earlier candidates ("From anywhere. Exactly as it is.", "Hundreds of formats. One clear choice.") were set aside.

## 2a. Plain-English principle (user requirement, 2026-11-14)

Most people don't know what a codec, container or bitrate is. Every choice in the app therefore has three layers,
written in plain English (no unexplained jargon; technical names appear second, in grey):

| Layer | Where | Example (codec "HEVC") |
|---|---|---|
| **Plain label** | on the pill itself | "Smaller · Apple" with "HEVC" underneath |
| **One-line meaning** | under the row, updates with the selection | "A newer format: about half the size of H.264 for the same picture. Plays on all recent Apple devices." |
| **Pros / cons** | "More about this" disclosure (as in the Compressor's `ExplanationView`) | ✓ Plays in QuickTime, Photos, iPhone · – Some older Windows PCs and TVs can't play it |

Rules: explanations are short (summary ≤ 25 words, ≤ 3 pros/cons), true for *this* video (they mention actual sizes and
what's available), and never alarmist. All text lives in one place (`DigbyDownloadCore/Explain/`) so it can be reviewed
and tested as a whole. A searchable **Glossary** (Help menu) collects every term.

## 3. Components (new, in addition to the shared set)

* `URLField` — the hero input: large (17 pt), rounded 12, paste button, accepts drag-and-drop, multi-line paste
  becomes a batch; validates as you type and shows the recognised site (favicon-free: site name + SF Symbol).
* `MediaPreviewCard` — thumbnail (16:9, 12 pt radius), title, uploader, duration, site; collapsible description.
* `ChoiceRow` — label + row of `PillButton`s; each pill can carry a secondary line (size, "Most compatible", "HDR").
  Unavailable options are simply absent; disabled-with-reason is used only for containers that would force conversion.
* `PlanSummary` — one sentence of what you'll get, with chips: "1080p · H.264 · AAC (English, original) · MP4 · ≈ 312 MB · no conversion".
* `LandfallProgress` — streaks descending toward the point as progress advances; indeterminate drift when size is unknown.
* `QueueRow`, `PlaylistGroup` (disclosure, per-item ticks), `DiagnosisCard` (what happened · what Digby is doing · what you can do).

## 4. States (each designed explicitly)

Empty · URL typed (recognised / not a link) · Analysing (sky panel, streaks drifting, title fills in as soon as known) ·
Ready (preview + choices) · Downloading · Completed (Dawn point, Reveal / Open / Compress with Digby) · Failed
(DiagnosisCard) · Updating engines (inline banner, never modal) · Diagnosing.

## 5. Rules

* No glass stacking: one material at most (the sidebar's), everything else solid window background + Cards.
* Gradients only in the sky panel, icon and prominent button — as in the Compressor.
* Light and dark from day one; every colour defined as a light/dark pair.
* Reduce Motion: streaks are static; progress is a plain bar-like line.
* VoiceOver: every pill reports its value and secondary line; progress reports percent and remaining time.
