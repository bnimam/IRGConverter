# Changelog

All notable changes to IRGConverter. Versions follow [semantic versioning](https://semver.org).

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
- **Six transform controls, set directly** — the infrared curve, both group curves,
  both subtractions and the output gamma. No abstraction over them: what the panel
  shows is what the transform uses, and a preset is a set of exactly these numbers.
  Each group has an ⓘ button giving the order to set them in and the symptom of each
  being wrong.
- **Source channel roles** — which file channel carries infrared, visible red and
  visible green. Defaults to infrared in **blue**, where a yellow-filtered
  full-spectrum camera puts it.

### Editing

- **Batch editing** — a filmstrip along the bottom, each photo owning its own edit.
  Finder-style selection (plain click, ⌘-click, ⇧-click), copy/paste of settings with
  three independent scope groups (the Aerochrome transform, the Adjust tab, RAW
  development), and *Apply to Selected* for the common case.
- **Adjust tab** — exposure, contrast, highlights, shadows, whites, blacks,
  saturation, vibrance, warmth, tint; master and per-channel tone curves with
  monotone cubic interpolation; and **sharpening** (a luminance unsharp mask with
  amount, radius and threshold).
- **Presets** — six built-in looks plus your own, saved as readable JSON in
  `~/Library/Application Support/IRGConverter/Presets`. *Aerochrome Magenta* is the
  default every photo starts on; the other five are that one with two or three numbers
  moved (Red, Bold, Subtle, Deep, and one for files already in IRG order). Each says
  what it changes, and a check renders all of them on a foliage-and-sky fixture to
  assert the direction of every claim. Export and import to share.
- **Preview Presets** — a sheet showing every preset as a tile of the photo you are
  working on, rendered from the preview already in memory: one downsample, then one
  transform per preset over the same prepared buffers. Click a tile to apply it. What
  a preset does depends on the frame, so seeing them beats reading their names.
- The preset menu keeps naming the preset a photo was started from even after a
  slider moves — a record of where the settings came from, not a claim that they are
  untouched.
- **Viewing aids** — Solo any one signal as grey, and a clipping overlay. Both are
  diagnostic: never saved into a preset, never applied on export, and the preview
  says so while either is on.
- **Histogram** with clipping readouts, plotted on a mild power curve because a
  false-colour render piles most of its pixels into a few narrow peaks.
- Double-click any control to reset just that control to the active preset, a paste,
  or the default. Every group has an ⓘ button explaining which way to
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
- `swift run IRGConverterCheck` runs 231 checks with no Xcode required — an
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
