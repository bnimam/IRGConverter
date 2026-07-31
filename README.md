# IRGConverter

**Version 1.0.0** · macOS 14+ · [Changelog](CHANGELOG.md)

**IRGConverter** is a native macOS application that converts (I)nfrared - (R)ed - (G)reen images to replicate the false-color film **Kodak Aerochrome**.

Built with SwiftUI and Accelerate, it processes images entirely on-device with no external dependencies.

---

## Table of Contents

- [Overview](#overview)
- [Equipment](#equipment--shooting-guide)
- [Shooting Tips](#shooting-tips)
- [Features](#features)
- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Option 1: Download the pre-built app](#option-1-download-the-pre-built-app)
  - [Option 2: Build from source](#option-2-build-from-source)
- [Usage](#usage)
  - [Interface](#interface)
  - [Batch editing](#batch-editing)
  - [Presets](#presets)
  - [Setting the transform](#setting-the-transform)
  - [Controls](#controls)
  - [Viewing aids](#viewing-aids)
  - [Adjust tab](#adjust-tab)
  - [Export](#export)
  - [Send to Lightroom](#send-to-lightroom)
- [Lightroom plugin](#lightroom-plugin)
- [Command line](#command-line)
- [Algorithm](#algorithm)
  - [Verifying the maths](#verifying-the-maths)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

This app is to recreate the Aerochrome look with a Full-spectrum digital camera. Aerochrome is a long dead
Kodak film which I believe was originally used for military and survey purposes. It's a false color film where
the blue sensitive layer is replaced with an infrared sensitive layer. By adding a yellow filter (and UV filter)
to a full spectrum converted camera, we are essentially emulating the way Aerochrome captures light. With
some magic channel swapping which comes from this [JW Wong post](https://www.flickr.com/photos/jw_wong/4960099202/)
(and inspired by [this video](https://www.youtube.com/watch?v=v5KBQd_DkQw))
we can re-create Aerochrome, but without needing to spend [$250+](https://www.ebay.com/sch/i.html?_nkw=kodak+aerochrome+film&_sacat=0&_from=R40&_trksid=p2334524.m570.l1313&_odkw=kodak+aerochrome&_osacat=0) on a roll.


| Input (Digital IR) | Output (Aerochrome Simulation) |
|-------------------|-------------------------------|
| ![](https://placehold.co/400x300/3a3a3a/aaaaaa?text=IR+Source) | ![](https://placehold.co/400x300/6b2fa0/aaaaaa?text=Aerochrome+Out) |

---

## Equipment 

As outlined above, you will need a full-spectrum camera, a yellow filter to block the blue light, and a 
UV filter to block the, well, UV light. You may also want to check out the [IR Hotspot Database](https://kolarivision.com/lens-hotspot-list/)
to avoid lenses which are known to have IR hotspotting.

TECHNICALLY you can actually shoot with other kinds of filters as well as the app just defaults
to assuming you are using a yellow filter, and presets may be added at some point for this, but
for now just Aerochrome.


## Shooting Tips

- Shoot at your lowest ISO since we're really working the color channels hard.
- Because of low ISO, be prepared to use a tripod.
- Shoot in bright sunlight, clouds may absorb too much IR light.
- Healthy vegetation will have the most striking effect.
- People's skin will look yellow, so don't expect flattering portraits.

---

## Features

- **One transform, transcribed from Photoshop** — A published Photoshop layer workflow, exactly: subtract infrared from the red and green groups, curves per group, then infrared→red, red→green, green→blue. Written out in full under [Algorithm](#algorithm).
- **Batch editing** — Load a whole shoot, click between photos in the filmstrip, copy one photo's settings onto the rest, and export the lot into a folder. Each photo keeps its own edit. See [Batch editing](#batch-editing).
- **Presets** — Six shipped looks plus your own, saved as readable JSON. All literal sets of numbers: applying one puts exactly those values on the sliders, so what a preset does is what you can read off the panel. Export and import to share, and a **Preview Presets** sheet that renders all of them as tiles of the photo you are working on. See [Presets](#presets).
- **Per-control guidance** — An ⓘ button on every group explains which way to move each slider and how to tell it is wrong.
- **Sharpening** — A luminance unsharp mask with amount, radius and threshold, applied after the curves. Radius is in the exported file's pixels, and a downsampled preview says so rather than faking it. See [Sharpening](#sharpening).
- **Adjustable preview resolution** — 600 px to full, so dragging stays responsive on big files.
- **Lightroom Classic plugin** — Send a selection from Lightroom straight into the app's filmstrip. See [Lightroom plugin](#lightroom-plugin).
- **Command line** — `irgconvert`, for scripted conversions. See [Command line](#command-line).
- **Real-time preview** — Adjust any parameter and see the result instantly on a downsampled preview. Renders are coalesced, so dragging a slider never queues up work that is already stale.
- **Measured RAW import defaults** — Neutral channel balance and one stop of highlight headroom, both chosen by measurement rather than taste. See [Adjust tab](#adjust-tab).
- **Always-on histogram** — RGB distribution of the result, top right of the preview, with shadow and highlight clipping readouts.
- **Basic photo editing** — Exposure, contrast, highlights, shadows, whites, blacks, saturation, vibrance, warmth and tint, plus a **curves** editor with master and per-channel curves.
- **Orientation aware** — EXIF orientation is baked in on load, so portrait frames are not shown sideways.
- **Source channel assignment** — Tell the app which channel holds infrared instead of having to pre-swap the file.
- **Parametric controls** — Independent scale, gamma and IR-crosstalk controls for the infrared and both visible signals.
- **Channel remapping** — Swap which recovered signal feeds each output RGB channel (similar to channel mixer in Photoshop).
- **16-bit pipeline** — Source decoded at 16 bits and kept there through development, orientation and downscaling; the transform runs in `Float`.
- **Back to Lightroom** — Send the current photo, the selection, or the whole strip out as 16-bit TIFFs beside the originals and straight into Lightroom's import. See [Send to Lightroom](#send-to-lightroom).
- **Full-resolution export** — HEIC at full original resolution, written from the 16-bit render into HEIC's 10-bit container, on a background thread. The full-size image is never held in memory; export re-develops from the file, so a RAW export honours the current development settings.
- **Drag-and-drop** — Drop one file or a whole selection onto the preview pane. Finder's *Open With* and dragging onto the Dock icon work too, as does passing paths on the command line.
- **Zero dependencies** — Pure Swift and Apple system frameworks.

---

## Installation

### Prerequisites

- macOS 14.0 (Sonoma) or later. That is all the downloaded app needs.
- To build it yourself, a Swift 5.9+ toolchain. Xcode is not required — Command Line
  Tools (`xcode-select --install`) is enough for `swift build`, `build_app.sh` and
  `swift run IRGConverterCheck`.

Get the app one of two ways — download it, or build it — then **move it into
`/Applications`**. Either route ends in the same place, and the app is expected to
live there: it is the first location the [Lightroom plugin](#lightroom-plugin) looks
in, and Finder's *Open With* only offers applications it can find.

### Option 1: Download the pre-built app

1. Open the [releases page](https://github.com/bnimam/IRGConverter/releases) and
   download `IRGConverter-1.0.0.zip`.
2. Unzip it — double-click in Finder, or:

   ```bash
   cd ~/Downloads
   unzip IRGConverter-1.0.0.zip
   ```

   Inside are the app, the Lightroom plugin with its installer, this README, the
   changelog and the licence.
3. Move the app into `/Applications` — drag it there in Finder, or:

   ```bash
   mv ~/Downloads/IRGConverter-1.0.0/IRGConverter.app /Applications/
   ```
4. The app is **ad-hoc signed, not notarized**, so Gatekeeper will refuse to open
   something downloaded from the internet. Clear the quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/IRGConverter.app
   ```
5. Open it:

   ```bash
   open /Applications/IRGConverter.app
   ```

### Option 2: Build from source

```bash
git clone https://github.com/bnimam/IRGConverter.git
cd IRGConverter
./build_app.sh
mv IRGConverter.app /Applications/
open /Applications/IRGConverter.app
```

`build_app.sh` builds the app and the `irgconvert` CLI, assembles the bundle next to
the repository, and ad-hoc signs it. A locally built bundle is never quarantined, so
step 4 above does not apply.

**Updating an installed copy.** Building again replaces `IRGConverter.app` in the
repository, not the copy in `/Applications`, and `mv` will not overwrite a bundle that
is already there (`Directory not empty`). Quit the app first — macOS keeps the old
executable mapped until you do, so a running app never shows the rebuild — then:

```bash
rm -rf /Applications/IRGConverter.app
mv IRGConverter.app /Applications/
```

To run without installing anything, straight from SwiftPM:

```bash
swift run
```

`./build_app.sh --zip` additionally writes `dist/IRGConverter-<version>.zip`, the
same archive the releases page carries. The version comes from one place,
`Sources/IRGConverterCore/Version.swift` — the build script reads it for the
bundle's `Info.plist` and the archive name, and `irgconvert --version` prints it.
The archive is built so that both `unzip` and Finder produce a bundle whose signature
still validates; see the comment in `build_app.sh` for the flags that requires and
why.

---

## Usage

### Interface

Launch the app and either click **Open Images…** or drag files onto the preview area. Select as many as you like — they all land in the filmstrip along the bottom. Camera RAW is developed neutrally (see [Features](#features)); anything else Core Graphics can decode (JPEG, PNG, TIFF, HEIC, BMP, …) is used as-is.

Then pick a preset and adjust the six transform controls from there. Everything on
the Adjust tab is for taste afterwards.

> **Where infrared lives.** Straight out of a yellow-filtered full-spectrum
> camera, infrared lands in the **blue** channel — the yellow filter blocks
> visible blue, but the Bayer array is transparent to IR, so the blue photosites
> see infrared and almost nothing else. Red sees even more infrared, but mixed
> with visible red, which makes it useless as a reference. That is the default. If
> your file is already swapped into IRG order (IR in red), set the **Source
> Channels** pickers by hand: IR ← red, Vis red ← green, Vis green ← blue.

### Batch editing

Everything in the panel edits **one** photo — the one with the bright border in the
filmstrip. Each photo owns its own settings, so dialling in the second frame does
not disturb the first. Settings move between photos only when you copy and paste
them.

**Getting photos in.** *Open Images…* takes a multiple selection, dropping a Finder
selection on the preview takes all of it, and the app also accepts files from
outside itself: Finder's *Open With*, a drag onto the Dock icon, or
`open -a IRGConverter --args a.ORF b.ORF`. Files already in the strip are skipped
rather than duplicated. An import selects what it just added, so the paste buttons
are useful immediately.

**Moving around.** Click a thumbnail to work on it. ⌘-click toggles one in or out of
the selection, ⇧-click extends from the current photo, and ⌘\[ / ⌘\] step backwards
and forwards. *Select All* and *Remove* act on the selection; right-clicking a
thumbnail also offers *Reveal in Finder*.

**Copying edits.** *Copy Settings* (⌘⇧C) takes the current photo's settings;
*Paste* (⌘⇧V) writes them onto every selected photo, and the ⌄ menu beside it
pastes to all photos instead. That menu also decides what a paste carries:

| Group | What it writes |
|---|---|
| **Aerochrome transform** | Everything on the Aerochrome tab: source channel roles, all four gammas, both subtractions, the output channel map, the black-and-white mode |
| **Tone, colour, curves & sharpening** | Everything on the Adjust tab |
| **RAW development** | Balance, temperature, tint and headroom — skipped for a destination that is not a RAW file |

Turning a group off leaves that part of the destination photo alone, which is how
you spread a look across frames that each needed their own exposure. The three
groups partition the settings exactly: nothing belongs to two of them, and nothing
to none, so pasting everything and pasting each group in turn give the same result.
A check asserts that. Values travel verbatim — nothing is re-derived on the way in,
so a paste reproduces exactly what the source photo showed.

*Apply to Selected* on the Aerochrome tab is the same thing in one click: copy the
current photo, paste to the selection.

**Reading the strip.** Thumbnails are converted, not raw, so the strip shows the
results. A dot means the photo's settings differ from the [default preset](#presets)
it arrived on; a green
tick means it has been exported since it was last changed; a red badge means its
export failed, and hovering says why.

**Exporting.** *Export* → *Export Selected…* or *Export All…* asks for a folder and
converts each photo at full resolution with its own settings. Output is
`<original name>_aerochrome.heic`. **Nothing is ever overwritten** — a name already
taken gets `-2`, `-3` and so on, because running a batch twice by accident is easy
and the first run's files are not recoverable from the second's. Progress and a
Cancel button sit in the toolbar; a file that fails is marked and the batch carries
on rather than stopping.

Exports run one at a time. That is not caution about CPU: a 20-megapixel frame is
re-developed at native size and the transform keeps about a dozen float planes of
scratch, so each photo costs on the order of a gigabyte while it is converting.
Measured on the sample ORF, 5184×3888 takes about 6.2 s per photo end to end
(develop, transform, encode).

Two costs were measured and moved off the main thread, because both are large
enough to freeze the window on a real import:

- Deciding whether a file is RAW and reading its pixel size each construct a
  `CIRAWFilter` — about **100 ms per file**. Forty files would have meant four
  seconds of dead UI, so photos are probed on a background queue and appear in the
  strip as they resolve.
- Thumbnails are real conversions at 220 px. The decode is the expensive part
  (**438 ms** for a RAW), so each photo's small source is cached: the first
  thumbnail costs 9 ms of transform after the decode, and every later one — every
  step of a slider drag — costs **about 1 ms**. Superseded renders are dropped
  rather than computed and thrown away.

### Presets

One preset ships, and it is also the default — every photo added to the filmstrip
starts on it, and `irgconvert` uses it when no `--preset` is given:

**Aerochrome Magenta** is the default — every photo starts on it, and `irgconvert`
uses it when no `--preset` is given. It was hand-tuned on a full-spectrum ORF: IR
gamma 1.13, subtractions 0.50 / 0.25, group curves 0.46 / 1.21, output gamma 2.63,
plus an S-curve on the master.

Every other built-in is that one with two or three numbers moved, so the set is a
family rather than a collection of unrelated starting points — and each one's notes
say exactly what it changes:

| Preset | What it changes | Measured on the sample frame |
|--------|-----------------|------------------------------|
| **Aerochrome Magenta** | *(the default)* | foliage 170,91,135 — pink |
| **Aerochrome Red** | green subtraction 0.25 → 0.55, which is what was keeping the blue output up | foliage 170,91,**94** — red, not pink |
| **Aerochrome Bold** | IR gamma → 1.55, red subtraction → 0.58 | mean chroma 72 → 115; foliage 184,47,86 |
| **Aerochrome Subtle** | IR gamma → 1.02, subtractions → 0.38 / 0.18 | mean chroma 72 → 54 |
| **Aerochrome Deep** | output gamma → 2.05 and a steeper curve | mean luma 102 → 65 |
| **Pre-swapped IRG** | source roles: infrared ← red, vis red ← green, vis green ← blue | for files already in IRG order |

One is worth a note: **Pre-swapped IRG** applied to a file that is *not* pre-swapped
produces nonsense by design, since it reads infrared out of the visible-red channel.

A preset is a literal set of numbers plus, optionally, how to develop a RAW file.
There is no derivation between the file and the sliders, so applying one and reading
the panel tells you the whole story. `IRGConverterCheck` renders every built-in on a
foliage-and-sky fixture and asserts the direction of each claim above, so a preset
cannot quietly stop doing what its notes say.

**Preview Presets…** opens every preset as a tile of the photo you are working on,
rendered from the preview already in memory: one downsample, then one transform per
preset over the same prepared buffers, since the decode is the expensive part and it
has already happened. Tiles appear as they land, and clicking one applies it. This
matters more here than in most editors — what a preset does depends on the frame,
because how much infrared a given subtraction leaves behind is a property of the
vegetation in front of the camera, not of the numbers alone.

The preset menu keeps naming the preset a photo was started from, even after a slider
has moved. It is a record of where the settings came from, not a claim that they are
untouched — the common case is *apply a preset, then adjust one control for this
frame*, and a label that blanked itself the moment anything differed left nothing on
screen saying which preset you were working from.

**Manage** offers:

- **Save Current Settings…** — writes a `.irgpreset` file into
  `~/Library/Application Support/IRGConverter/Presets`.
- **Export Current Settings… / Export All My Presets…** — writes anywhere, for
  sharing or version control.
- **Import Presets…** — reads one or many files. Names that collide gain a
  numeric suffix rather than overwriting what you already had.
- **Reveal Presets Folder**.

Preset files are plain JSON and safe to hand-edit. Missing fields fall back to
the default rather than failing the load, and a file may hold a wrapped
collection, a bare array, or a single bare preset:

```json
{
  "formatVersion": 1,
  "presets": [
    {
      "name": "My Preset",
      "notes": "what this one is for",
      "params": { "gammaBy": 1.13, "gammaRx": 0.46, "subtractIRRed": 0.75 },
      "raw": { "useNeutralBalance": true, "exposure": -1 }
    }
  ]
}
```

### Setting the transform

The six transform controls are set directly — there is no layer of abstraction over
them. What the panel shows is what the transform uses, and a preset is just a set of
these numbers:

| Control | Range | What it does |
|---|---|---|
| **Infrared Group → IR gamma** | 0.1 … 10 | The curve on the infrared group. The strongest single control: it decides how bright infrared is and therefore how red foliage goes. |
| **Red Group → gamma** | 0.1 … 10 | The curve *above* the red group's Subtract layer, so it shapes what survived the subtraction. |
| **Red Group → subtract** | 0 … 2 | How much infrared comes out of the red group. Raise until soloed foliage is nearly black, then back off. |
| **Green Group → gamma** | 0.1 … 10 | The curve *below* the green group's Subtract layer, so it runs first and feeds the subtraction. |
| **Green Group → subtract** | 0 … 2 | How magenta foliage is. Higher takes leaves toward pure red; lower keeps them pink. |
| **Output → Gamma** | 0.25 … 4 | The final curve over the composite. Lower is denser. |

Each group heading has an **ⓘ** button giving the order to set them in and the
symptom of each one being wrong, and a **Solo** checkbox that shows that signal on
its own — which is the only reliable way to judge a subtraction. See
[Viewing aids](#viewing-aids).

Gamma sliders use a logarithmic track, so 1.0 sits in the middle instead of being
crammed against the left edge.

#### Why there are no Look dials

Earlier versions had three dials — Strength, Magenta, Density — computing the
infrared curve, both subtractions and the output gamma from the calibration. They
have been removed. The problem was ownership: a hand-tuned control silently detached
from its dial, and then any later touch of a dial took it back, so the panel could
not tell you which numbers were yours. Presets had the same split personality, one
storing dials and another storing values. Six sliders and a set of presets say the
same things with none of that.

The measurements the dials were fitted against are still the shipped defaults, and
they are still recorded in `AerochromeCalibration` — IR gamma 2.15, subtractions 0.30
and 0.10, output gamma 1.85, on the reference frame.

#### Why the measurement-based auto-tune was removed

An earlier version had an **Auto** button that measured the image: it picked the
infrared channel by a correlation score, estimated the crosstalk from percentile
ratios, and transferred a calibration onto the result. It has been taken out,
because it did not work well enough to trust:

- The channel score was fooled by any frame where two channels happened to be
  proportional to each other. On a synthetic test it confidently picked green.
- The crosstalk estimate assumed the brightest infrared in the frame was pure
  vegetation. Often it is a white wall.
- Every attempt to derive the six controls from those measurements landed somewhere
  wrong. Fitting each group's curve to its own highlights drove gamma to the rails
  and turned foliage **yellow**; capping the curve to keep vegetation dark crushed
  the visible groups and turned the sky **orange**; fitting all six against
  percentile-derived populations over-subtracted.

The root cause is worth recording, because it also explains why the red group needs
both of its controls set together: `Red Group → subtract` and `Red Group → gamma` do
the same job between them. The subtraction removes most of the infrared and the curve above it,
being below 1, squashes what is left. Full analytic cancellation wants a subtraction
near `0.85`; the calibrated value is `0.30`, because the curve finishes the work.
Solving either in isolation lands nowhere near the pair that looks right.

### Controls

Once an image is loaded, the control panel on the right provides the following adjustments:

| Group | Controls | Description |
|-------|----------|-------------|
| *(tab)* | Aerochrome / Adjust | Transform controls, or ordinary photo editing. See [Adjust tab](#adjust-tab). |
| **Presets** | Choose…, Preview Presets…, Manage | The six built-in looks and your own. See [Presets](#presets). |
| **Source Channels** | IR ←, Vis red ←, Vis green ← | Which file channel holds each signal. Defaults to IR = blue. |
| **Infrared Group** | IR gamma | Curves on the blue group. The strongest single control — it sets how red the foliage goes. |
| **Red Group** | gamma, subtract | The curve *above* the Subtract layer, and that layer's opacity. |
| **Green Group** | gamma, subtract | The curve *below* the Subtract layer, and that layer's opacity. |
| **Output** | Gamma, R ←, G ←, B ← | The final curves layer, and which signal drives each output channel. |
| **Solo** *(checkbox on each group)* | Infrared, Red, Green | Show that one signal on its own as grey. See [Viewing aids](#viewing-aids). |
| **Show clipping** | — | Mark pixels crushed to 0 (blue) or pushed to 255 (red). |

Every control has an **ⓘ** button next to its group heading. That opens a popover
saying what the control is in the Photoshop layer stack, how to tell it is set
wrong, and which way to move it — worth more than the definition, since these
controls interact.

Gamma sliders use a logarithmic track, so 1.0 (neutral) sits at the middle
rather than being crammed against the left edge.

**Double-clicking any control** resets just that control to whatever was last
applied as a whole — the active preset, a paste, or the shipped default. The panel says which, and each control's tooltip shows the value it
will snap back to. Resetting the one control you had nudged brings the preset
label back, since the settings match the preset again.

**Reset to Default** puts every parameter back to the default preset —
[Aerochrome Magenta](#presets), where the photo started. **Show Original** toggles
between the processed preview and the untouched source.

### Adjust tab

Everything on this tab sits *after* the Aerochrome transform, and is left alone
by the six transform controls — an edit made here survives moving them. A preset
does replace it, since a preset carries its own curve.

#### Preview

How large an image the live preview is computed from: 600 px up to full
resolution. Lower is faster to drag; higher shows the real detail and noise, which
matters when judging the subtraction on fine foliage. Export is always full
resolution regardless — it re-develops from the file. It has no effect on the
settings: nothing is measured from the image, so the numbers are the same at every
resolution.

#### RAW Development

Shown only for RAW files. Changing anything here re-develops from the sensor
data; the decode runs at preview size and off the main thread, so dragging is
responsive, and export re-develops at full resolution with whatever is set.

| Control | Default | Why |
|---|---|---|
| **Neutral balance** | on | Balances the three channels equally. The transform needs this to tell infrared from visible. |
| **Temp K / Tint** | 5500 K / 0 | Active only with neutral balance off. 5500 K is nominal daylight, which is what this app's subject matter is shot in. |
| **Headroom** | −1.0 EV | Protects the red channel, which clips first on a yellow-filtered capture. |

Those two defaults are measured, not chosen by eye. On the sample frame:

| development | IR channel picked | visible agreement | IR leak | red clipped |
|---|---|---|---|---|
| as shot | green (wrong) | 0.904 | 0.754 | 9.8% |
| neutral, 0 EV | blue | 0.880 | 0.517 | 9.6% |
| **neutral, −1 EV** | **blue** | **0.944** | **0.496** | **0.8%** |
| 5500 K, −1 EV | blue | 0.935 | 0.566 | 1.0% |
| 2500 K, 0 EV | green (wrong) | 0.981 | 0.821 | 0.7% |

Two separate problems needing two separate levers:

- **Balance.** A full-spectrum camera's as-shot white balance is calibrated for
  visible light it can no longer see. Applied, it pushes red to clipping, crushes
  green, and the infrared channel can no longer be identified — the measurement
  picks green instead of blue. Note that a *colour temperature* cannot fix this:
  cooling far enough to stop red clipping (2500 K) squashes the channels together
  and loses the infrared channel just as badly.
- **Level.** Clipping is a level problem, so exposure fixes it. One stop of
  headroom drops clipped red pixels from 9.6% to 0.8% and, because of that,
  *raises* agreement between the two recovered visible channels from 0.880 to
  0.944. Nothing is given up: a darker input simply needs a little more infrared
  gamma, and the shipped presets are already fitted against these defaults.

#### Tone and Colour

| Control | Notes |
|---|---|
| **Exposure** | Stops. Applied first. |
| **Contrast** | Gain about a 0.5 pivot. |
| **Highlights / Shadows** | Tonal-region lifts. Scaled so neither can take a value *past* black or white; the cost is a gentler maximum shift of about 0.15. |
| **Whites / Blacks** | Endpoint moves. Positive opens the range, negative compresses it. |
| **Saturation** | Chroma scaling about luminance. |
| **Vibrance** | Saturation weighted by how unsaturated the pixel already is, so it lifts muted colour without pushing already-vivid foliage further. |
| **Warmth / Tint** | Red/blue and green/magenta tilts. |

#### Sharpening

An unsharp mask, applied last — after the tone curves, because what it amplifies is
the edge contrast of the picture as rendered. Sharpening *before* a curve that lifts
the shadows five times over would put five times the halo there.

| Control | Range | Notes |
|---|---|---|
| **Amount** | 0–2, default **0** | How much of the detail layer goes back. Off by default: sharpening is a per-image decision, not part of a look. Past about 1.0 edges start showing a bright outline. |
| **Radius** | 0.3–3 px, default 1.0 | The size of detail it acts on, in pixels **of the full-size file** — see below. Around 1 px is texture; 2–3 px is local contrast, usually too much for foliage. |
| **Threshold** | 0–25 levels, default 0 | Detail quieter than this is left alone. A full-spectrum capture developed with headroom has noise in the sky and the shadows, and sharpening amplifies noise exactly as willingly as edges. |

It runs on **luminance**: blur the Rec. 709 luminance, subtract to get the detail
layer, add the same grey delta back to all three channels. One blur instead of
three, and it cannot shift hue — per-channel sharpening does, and the reds this look
produces are close enough to saturation to show it as coloured fringing. The knee on
the threshold is smooth (`d² / (d² + threshold²)`) rather than a hard cut, which
would leave a visible boundary where detail crosses it. Overshoot is clipped back
into range, since `vDSP_vfixru8` downstream wraps rather than saturating.

Cost, measured on the 5184×3888 sample frame: **1.15 s → 1.18 s** for a full
conversion, so about **30 ms** for the whole stage. Radius 3 costs the same as
radius 1 — the two convolution passes are separable (2k multiplies per pixel rather
than k²) and the scalar pass over the three planes dominates.

**Radius is in the exported file's pixels, and a small preview cannot show that.**
A 1 px radius on a 1200 px preview of a 5184 px frame is 0.23 px, which is below the
floor where a blur and its input still differ — so the render **skips** sharpening
there rather than exaggerating the radius to make it visible. The panel says which
case you are in, and the honest place to judge it is **Preview → Full**. Export and
*Send to Lightroom* always apply it, since they run at full resolution. Filmstrip
thumbnails never show it, for the same reason at 220 px.

#### Curves

Master (RGB) plus per-channel R, G and B curves. Drag a point to move it, click
empty space to add one, double-click a point to remove it. The endpoints move
vertically only, so the curve always spans the full input range. The channel's
histogram is drawn behind the grid, so an adjustment can be aimed at tones that
actually exist in the frame.

Curves are evaluated with **monotone cubic** interpolation (Fritsch-Carlson
tangent limiting). A natural spline or plain Catmull-Rom through the same points
overshoots, which on a tone curve shows up as banding and as reversals — a curve
that dips darker exactly where you asked for brighter. The limited version is
guaranteed monotone wherever the control points are, and is checked as such.

#### Histogram

Always visible, top right of the preview. Bins are plotted on a mild power curve
rather than linearly: a false-colour render piles most of its pixels into a few
narrow peaks, and a linear plot flattens everything else to an invisible line
along the axis. The clipping readouts turn orange past 1% of pixels pinned.

### Viewing aids

The subtraction and gamma controls are hard to set from the finished composite:
infrared still left in a channel and a channel over-subtracted into nothing both
just look like "dark foliage". The checkbox beside each channel heading answers it
directly.

**Solo** shows one signal on its own, as grey, bypassing the output channel map
*and* the Adjust tab — so what is on screen is what the transform produced and
nothing else. With the subtraction set correctly, soloed **Visible Red** looks
like an ordinary black-and-white photograph in which the vegetation is nearly
black, because healthy leaves really do reflect almost no visible red. Measured on
the sample frame's foliage patch:

| subtractIRRed | soloed visible red |
|---|---|
| 0.00 | 242 |
| 0.40 | 109 |
| 0.75 | 0 |
| 1.10 | 0 |

Grey foliage means too little subtraction. Flat black over a wide area means too
much — and note the auto-derived 0.75 sits right at the crush point, so backing
off slightly is what keeps some detail in the leaves.

**Show clipping** paints pixels whose darkest channel has been crushed to 0 in
blue and whose brightest has been pushed to 255 in red, blown winning where both
apply. Most useful with a channel soloed: at `subtractIRRed = 1.8` the sample
frame goes almost entirely blue, which is over-subtraction you cannot see any
other way.

Both are **view only**. They are not part of `AerochromeParams`, so they cannot be
saved into a preset and the export path cannot pick one up; the preview shows an
orange banner while either is on.

### Export

**Export** → **Save This Photo…** writes the full-resolution result of the photo on
screen; the other two entries convert the selection or the whole strip into a folder
(see [Batch editing](#batch-editing)). **HEIC only** — one
format, no decision to make. The export runs on a background thread against its own
processor instance, so the live preview keeps working while a large file encodes,
and it re-develops from the file rather than holding a full-size decode in memory.
A 5184×3888 frame takes about half a second and lands around 13 MB.

The file is written from the **16-bit** render rather than the 8-bit preview one,
because HEIC stores 10 bits per channel and there is no reason to hand it
pre-quantized data. The whole pipeline is 16-bit to match: the source is decoded at
16 bits and kept there through RAW development, orientation and downscaling, and
the transform runs in `Float`. That matters more than it sounds — the infrared
group's curve is typically around 2.2, and `v ^ (1/2.2)` stretches the bottom of
the range by roughly five times, so an 8-bit decode puts banding in exactly the
areas the look depends on. Measured, the infrared output carries 19,361 distinct
levels; before the load path was fixed to stay at 16 bits it carried 101.

How much the 16-bit *source* buys in the exported file is worth stating honestly.
On a synthetic smooth ramp it is dramatic — 924 distinct levels against 256. On a
real photograph most of it is masked by HEIC's own lossy compression, which
generates plenty of distinct values on its own: on the sample frame the red and
green outputs come out the same either way, and only the blue output, the most
heavily crushed channel, clearly benefits (50,084 levels against 26,709). Smooth
skies and shadow gradients are where it shows. It costs nothing, so it is worth
doing, but it is not a transformation of the output.

### Send to Lightroom

**Export** sits next to **Send to Lightroom**, which does the return half of the
round trip: *Send This Photo*, *Send Selected*, or *Send All* converts at full
resolution, writes the results **beside the originals**, and opens them in
Lightroom — the same thing dropping files on Lightroom's icon does, so they arrive
in front of the Import dialog.

The hand-off format is **16-bit TIFF**, not HEIC. TIFF has no 10-bit mode — the
format stores 8 or 16 bits per channel — and 16 bits is a superset of what HEIC's
10 could hold, carries the render exactly, and is what Lightroom wants from another
editor. Verified rather than assumed: written and read back, a 16384-value ramp
returns bit-identical (worst Δ0) at 16 bits per component with the sRGB profile
attached.

It is written **uncompressed**, which is also measured. On the 5184×3888 sample
frame every option is lossless and comes back exact, so only size and time differ:

| compression | size | vs raw | write |
|---|---|---|---|
| **none** | **120 MB** | **100%** | **106 ms** |
| LZW | 155 MB | 128% | 816 ms |
| deflate | 116 MB | 95% | 2218 ms |
| PackBits | 121 MB | 100% | 255 ms |

LZW *expands* the file: it looks for runs of repeated bytes and 16-bit
photographic data has none in its low-order bits. Deflate saves 4% for twenty times
the write cost. So: uncompressed, which is also the most widely readable choice for
a file whose whole job is to be opened by something else.

Budget the disk. About **120 MB per 20-megapixel photo** — sending forty frames
writes roughly 5 GB. Nothing is overwritten; a second send of the same photo lands
as `-2`.

If Lightroom is not installed the send stops before converting anything and says so,
rather than spending minutes on files it cannot hand over.

Two platform details behind all this, both measured rather than assumed:

- `CGContext.draw` into a 16-bit-per-component context silently produces all
  zeros, so every 16-bit step uses `CIContext.render` or `createCGImage(format:)`
  instead.
- `CIContext.createCGImage` defaults to 8 bits. Developing a RAW without passing
  `format: .RGBA16` throws away the depth before the transform ever sees it.
- Quality 1.0 is not better than 0.95 for HEIC: measured, it produces *fewer*
  distinct levels while more than doubling the file size.

---

## Lightroom plugin

A Lightroom **Classic** plugin lives in [`LightroomPlugin/`](LightroomPlugin/). It
does one thing: sends the photos selected in Lightroom to IRGConverter.app.

```bash
./build_app.sh                      # builds the app
cp -R IRGConverter.app /Applications
./LightroomPlugin/install.sh        # copies the plugin into Lightroom's Modules
```

Then, in Lightroom Classic: **File > Plug-in Manager** should list *IRGConverter*.
Select photos and choose **Library > Plug-in Extras > Open in IRGConverter** (the
same item also appears under File > Plug-in Extras). The app comes to the front with
those files in its filmstrip, ready to edit and export as a batch.

Nothing else is integrated, by design. The catalogue is not written to, no rendition
is exported, and no Develop settings are touched — the plugin passes the **original
file paths**, so the conversion starts from the sensor data rather than from a
Lightroom rendering.

Coming back the other way is the app's own **Send to Lightroom** button: it writes
16-bit TIFFs beside the originals and opens them in Lightroom's import. Together
that is the whole loop — select in Lightroom, convert in IRGConverter, back to
Lightroom for the finishing. See [Send to Lightroom](#send-to-lightroom).

Details worth knowing:

- **Target photos, not just selected ones.** With nothing selected, Lightroom's
  "target photos" is the whole filmstrip, which is what every other Lightroom
  command does.
- **Virtual copies collapse.** Several virtual copies of one master share a file, so
  duplicates are dropped rather than opened repeatedly.
- **Offline masters are skipped and counted.** If some files are not on this machine
  the rest still open, and a dialog says how many were left behind.
- **Finding the app.** The path set in the Plug-in Manager wins, then
  `/Applications`, `~/Applications`, then next to this repository, and finally
  Spotlight by bundle identifier (`com.irg.IRGConverter`).
- Lightroom Classic only. Lightroom (the cloud one) has no plugin SDK of this kind.

### Why it is not deeper than that

Negative Lab Pro does part of its work by writing values into Lightroom's **own
Develop sliders**, which is why its conversions stay live and re-editable in the
Develop module. That approach is not available here: this transform subtracts one
channel from another, and nothing in Lightroom's Develop module can express that —
not the tone curve, not the per-channel curves, not HSL. There is also no plugin API
for injecting custom pixel processing into the Develop pipeline.

A previous version of this plugin took the other road a Lightroom plugin can take: a
post-process export filter that converted each rendered frame through the
`irgconvert` binary. It worked, but it meant every change of mind was another full
export, the render had to be forced to 16-bit TIFF to avoid banding, and the
converted files had to be re-imported to be seen. Handing the originals to the app
is less machinery for a better loop — the filmstrip, live sliders, and one folder
export at the end. The [command line](#command-line) tool is still there for anyone
who wants the automated path.

### What has and has not been tested

**Lightroom is not installed on the machine this was written on, so the plugin has
never been loaded into Lightroom.** Treat the SDK integration — the menu
registration and the catalogue calls — as unverified.

What *is* verified, by [`LightroomPlugin/test_plugin.lua`](LightroomPlugin/test_plugin.lua):
all four Lua files parse under `luac -p`, and the plugin's non-UI logic runs with the
SDK modules stubbed — app lookup and the preference override, every fallback path in
the search order, the Spotlight fallback against the real bundle, collecting files
from a selection (order, virtual-copy dedupe, offline masters, missing paths, a path
that does not start with `/`), shell quoting including a single quote inside a
filename, and refusing an empty list. With `--launch` it also really runs `open` and
checks that the app accepts the file.

```bash
lua LightroomPlugin/test_plugin.lua /Applications/IRGConverter.app
lua LightroomPlugin/test_plugin.lua IRGConverter.app example_raw/P7290001.ORF --launch
```

---

## Command line

`irgconvert` converts one file without opening the app, for scripts and Automator. It
ships inside the app bundle at `IRGConverter.app/Contents/MacOS/irgconvert`, or run
it from source with `swift run irgconvert`.

```bash
irgconvert --input P7290001.ORF --output out.heic
irgconvert --input P7290001.ORF --output bold.heic --preset "Aerochrome Bold"
irgconvert --input P7290001.ORF --output punchy.heic --ir-gamma 1.5 --green-subtract 0.55
irgconvert --list-presets
```

| Option | |
|---|---|
| `--input` / `--output` | Source, and destination. Always written as HEIC. |
| `--preset <name>` | Start from a named preset, the default or one of yours. Omitted, the [default preset](#presets) is used — the same starting point as the app. |
| `--ir-gamma` / `--red-gamma` / `--red-subtract` / `--green-gamma` / `--green-subtract` / `--output-gamma` | The six [transform controls](#setting-the-transform), each in the same units as its slider. Given here, they override the preset's. |
| `--sharpen <0..2>` / `--sharpen-radius <px>` / `--sharpen-threshold <levels>` | [Unsharp mask](#sharpening). Amount 0 is off. Full resolution here, so the radius needs no scaling. |
| `--ir-channel <r\|g\|b>` | Which source channel holds infrared. Default `b`. |
| `--headroom` / `--temperature` / `--tint` | RAW development. See [Adjust tab](#adjust-tab). Given here, they beat the preset's. |
| `--version` / `--help` | Print the version, or the option list. |

It reads the same presets folder as the app, so a preset saved in the GUI is
available by name here.

---

## Algorithm

The processing pipeline operates entirely on normalized floating-point pixel buffers via Apple's Accelerate framework (vDSP).

There is **one** transform, and it is a direct transcription of a Photoshop layer
workflow — isolate the three groups, subtract infrared from two of them, curve each,
then mix the groups onto swapped output channels:

```
irSignal = ir ^ (1 / irGamma)                                             // blue group curves
redSig   = max(visRed - redSubtract * irSignal, 0) ^ (1 / redGamma)       // Subtract, then curves
greenSig = max(visGreen ^ (1 / greenGamma) - greenSubtract * irSignal, 0) // curves, then Subtract
out[c]   = signal[map[c]] ^ (1 / outputGamma)
```

Photoshop's Subtract clamps at zero and layer opacity scales the subtrahend, so
`base − opacity × blend` clamped at 0 is exact. Dragging the centre of a Curves
adjustment is a gamma move, so every curve here is `v ^ (1 / gamma)` with gamma
above 1 brightening. Screening channel-isolated groups is plain recombination.

The **curve order** is the part that matters and the easy thing to get wrong: the
document puts red's curves adjustment *above* its Subtract layer and green's
*below*, so red is curved after subtraction and green before. Both orders are
checked against a scalar transcription.

Earlier versions also shipped a reverse-extraction model and the original forward
mixing model. They have been removed: this one gives visibly better results, and
keeping three near-equivalent transforms meant three sets of defaults and three lots
of documentation for no gain.

Steps:

1. **Decompose** — Split the source into three float planes and cache `1 - channel` for each. Which plane plays which role is a parameter, so changing the assignment costs nothing.
2. **Transform** — The stack above, as five `vvpowf` passes and a handful of `vDSP` vector ops.
3. **Channel remapping** — The default is `R ← infrared`, `G ← visible red`, `B ← visible green`: the Aerochrome false-colour shift. Infrared-bright foliage goes crimson, and visible-red surfaces such as brick or brown wood go green.
4. **Adjustments** — Exposure, endpoints, tonal lifts, contrast, colour tilts and saturation, in one fused pass over the three planes. Deliberately a scalar loop rather than fifteen `vDSP` passes: saturation and vibrance need all three channels of a pixel at once, the tonal masks are cheap polynomials, and one pass touches each pixel's memory once instead of fifteen times. Skipped entirely when nothing is set.
5. **Curves** — Master and per-channel curves are composed into one 256-entry table per channel and applied by interpolated table lookup, so the cost is a single lookup per channel regardless of how many control points there are.
6. **Sharpening** — A luminance unsharp mask, last, so what it amplifies is the edge contrast of the finished picture. Two separable vImage convolution passes over one luminance plane rather than three per-channel blurs. See [Sharpening](#sharpening).

### Verifying the maths

The vectorized pipeline is checked against a scalar transcription of the
equations above — both transforms, several parameter sets, edge cases for pure
black/white, odd image widths and row padding, plus every built-in preset,
the viewing aids, the copy/paste groups, the batch
export naming and both export formats — including a TIFF round trip that has to come
back bit-identical. Sharpening gets its own section: overshoot on both a horizontal
and a vertical edge (so both convolution passes are exercised), flat areas left
alone, hue held, a kernel that sums to one, the threshold holding fine ripple back,
1×1 and 1×16 images not crashing the convolution, and a downscaled render skipping
the mask rather than faking it. It is an executable rather than an XCTest
target so it runs on a bare Command Line Tools install:

```bash
swift run IRGConverterCheck
```

---

## Roadmap

In no particular order

- [x] Preset save / load / export / import system
      (`~/Library/Application Support/IRGConverter/Presets`)
- [x] Basic photo editing sliders and a curves tool
- [x] Adjustable preview resolution
- [x] Clickable per-control guidance
- [x] Batch processing (filmstrip, copy/paste of edits, folder export)
- [x] Histogram display
- [x] Send results back to Lightroom as 16-bit TIFFs
- [x] Sharpening (luminance unsharp mask: amount, radius, threshold)
- [ ] Waveform display
- [ ] Undo history
- [x] Infrared bleed preview to fine tune (solo + clipping viewing aids)
- [x] Double click to reset a control to the preset, a paste, or the default
- [x] Source channel role picker, for shooting straight off a yellow-filtered
      full-spectrum camera without pre-swapping to IRG order
- [x] Direct transform controls with a family of presets over them (replaced the Look dials, which replaced the measurement-based auto button)
- [ ] In app instructions for fine tuning for your camera + lens + filter combo
- [x] Lightroom Classic plugin (sends the selection to the app)
- [x] Command-line converter
- [ ] Verify the Lightroom plugin against an actual Lightroom install

---

## License

[GNU Affero General Public License v3.0](LICENSE) — See `LICENSE` for the full text.
