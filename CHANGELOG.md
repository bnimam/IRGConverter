# Changelog

All notable changes to IRGConverter. Versions follow [semantic versioning](https://semver.org).

## 1.1.0 — 2026-07-30

The transform is now set directly instead of through dials, and there is a family of
presets over it.

### Added

- **A family of presets.** *Aerochrome Magenta* is still the default every photo
  starts on; *Red*, *Bold*, *Subtle*, *Deep* and *Pre-swapped IRG* are each that one
  with two or three numbers moved. Each says what it changes, and a check renders all
  six on a foliage-and-sky fixture to assert the direction of every claim.
- **Preview Presets…** — every preset as a tile of the photo you are working on,
  rendered from the preview already in memory: one downsample, then one transform per
  preset over the same prepared buffers. Click a tile to apply it. What a preset does
  depends on the frame, so seeing them beats reading their names.
- **Zoom and pan.** **Fit**, **100%** and **200%** in the top bar. 100% is one image
  pixel per *device* pixel, so the zoomed levels render the frame at native size
  rather than magnifying a downsampled proxy; drag the photo to move around it.
- **A histogram toggle**, and the preview-resolution menu, both moved to the top bar.
- Six transform flags on `irgconvert` — `--ir-gamma`, `--red-gamma`,
  `--red-subtract`, `--green-gamma`, `--green-subtract`, `--output-gamma` — replacing
  the dial flags.

### Changed

- **The six transform controls are set directly.** The Look dials (Strength, Magenta,
  Density) are gone. They owned four of the controls, so a hand-tuned value silently
  detached from its dial and any later dial move took it back, leaving the panel
  unable to say which numbers were yours. Presets had the same split personality, some
  storing dials and some storing values.
- **The preset menu keeps naming the preset a photo was started from**, even after a
  slider moves. It is a record of where the settings came from, not a claim that the
  numbers are untouched.
- Copy/paste scope groups: four → **three** (the Aerochrome transform, the Adjust tab,
  RAW development). They still partition the settings exactly.
- The release archive is `IRGConverter.zip` — unversioned, so the download link in the
  README does not go stale — and carries the app, the Lightroom plugin with its
  installer, the README, the changelog and the licence. It is built so that both
  `unzip` and Finder produce a bundle whose signature still validates.
- The README is about a third of its former length, with screenshots and a
  step-by-step install for both the app and the Lightroom plugin.
- `swift run IRGConverterCheck` now runs 231 checks.

### Removed

- **Black and white.** The monochrome modes and their two presets are gone; *Solo*
  still renders one signal as grey, since that is a diagnostic rather than part of the
  image.
- `--strength` / `--magenta` / `--density` and `--mono` from `irgconvert`.

### Compatibility

Presets and edits written by 1.0.0 still load. Those files carry `look` and
`usesLook`, which are now ignored — 1.0.0 stored `params` as the values actually on
its sliders, so the numbers come back as they were and nothing is re-derived. A check
covers a preset from each era.

## 1.0.0 — 2026-07-30

First release. Converts infrared/red/green photographs to the Kodak Aerochrome
false-colour look, one at a time or a shoot at a time.

### The transform

- One transform, transcribed from the Photoshop layer workflow: subtract infrared
  from the red and green groups, a curve per group, then infrared → red, red →
  green, green → blue, and a final curve over the composite. Red's curve sits
  *above* its Subtract layer and green's *below*, which is the part that is easy to
  get wrong.
- Runs on normalized float planes through Accelerate (vDSP), and is checked against
  a scalar transcription of the equations.
- **Look dials** — Strength, Magenta and Density drive the six group controls as a
  pure function of the calibration, so the same settings give the same numbers on
  every frame. Move a group control by hand and it detaches until a dial or a preset
  sets it again.
- **Source channel roles** — which file channel carries infrared, visible red and
  visible green. Defaults to infrared in **blue**, where a yellow-filtered
  full-spectrum camera puts it.
- **Black and white** from the infrared signal alone, either visible band, or the
  composite's luminance.

### Editing

- **Batch editing** — a filmstrip along the bottom, each photo owning its own edit.
  Finder-style selection (plain click, ⌘-click, ⇧-click), copy/paste of settings
  with four independent scope groups (Look, channels, tone, RAW development), and
  *Apply to Selected* for the common case.
- **Adjust tab** — exposure, contrast, highlights, shadows, whites, blacks,
  saturation, vibrance, warmth, tint; master and per-channel tone curves with
  monotone cubic interpolation; and **sharpening** (a luminance unsharp mask with
  amount, radius and threshold).
- **Presets** — one shipped default look, *Aerochrome Magenta*, plus your own saved
  as readable JSON in `~/Library/Application Support/IRGConverter/Presets`. Export
  and import to share.
- **Viewing aids** — Solo any one signal as grey, and a clipping overlay. Both are
  diagnostic: never saved into a preset, never applied on export, and the preview
  says so while either is on.
- **Histogram** with clipping readouts, plotted on a mild power curve because a
  false-colour render piles most of its pixels into a few narrow peaks.
- Double-click any control to reset just that control to the active preset, the last
  Look change, or the default. Every group has an ⓘ button explaining which way to
  move its controls and how to tell they are wrong.

### RAW and output

- **Measured RAW import defaults** — neutral channel balance and one stop of
  highlight headroom, both chosen by measurement rather than taste: together they
  drop clipped red pixels from 9.6% to 0.8% and raise agreement between the two
  recovered visible channels from 0.880 to 0.944.
- 16 bits per channel end to end — decode, orientation, downscale, transform and
  write.
- **Export** — a single photo through a save panel, or the selection or the whole
  strip into a folder, at full resolution with each photo's own settings. Nothing is
  ever overwritten: a taken name gains `-2`, `-3`, and so on.
- **Send to Lightroom** — writes 16-bit uncompressed TIFFs beside the originals and
  opens them in Lightroom. Uncompressed is measured, not lazy: on the sample frame
  LZW *expands* the data to 128% of raw, and deflate saves 4% for twenty times the
  write cost.
- **Adjustable preview resolution**, 600 px to full, so dragging stays responsive on
  big files. Renders and decodes are coalesced — a slider drag never computes work
  that is already stale.

### Around the app

- **Lightroom Classic plugin** — *Library > Plug-in Extras > Open in IRGConverter*
  sends the selected photos' original files to the app. It writes nothing and leaves
  the catalogue untouched.
- **Command line** — `irgconvert`, shipped inside the app bundle, for scripted
  conversions.
- Files can arrive by drag and drop, an open panel, Finder's *Open With*, a drop on
  the Dock icon, or as command-line paths.
- `swift run IRGConverterCheck` runs 206 checks with no Xcode required — an
  executable target rather than an XCTest one, so it works on a bare Command Line
  Tools install.

### Known limitations

- The app is **ad-hoc signed, not notarized**. Gatekeeper will object on a machine
  that did not build it; `xattr -dr com.apple.quarantine IRGConverter.app` clears it.
- The Lightroom plugin has **not been run against a real Lightroom install** — there
  is none on the development machine. Its search order, file collection and shell
  quoting are covered by `LightroomPlugin/test_plugin.lua` (18 checks, including a
  real `open`), but the SDK integration itself is unverified.
- Sharpening is **not shown in a downsampled preview**, by design: a radius under a
  third of a pixel has no detail layer to add back, so the render skips it rather
  than exaggerating it. Judge sharpening at *Preview → Full*; export always applies
  it.
- No undo history. Double-click resets one control; *Reset to Default* and *Reset
  Adjustments* reset a group.
- Export is HEIC (or 16-bit TIFF for the Lightroom hand-off). No JPEG or PNG.

## 0.1.0

Initial working app: the transform, a live preview, and single-file export.
