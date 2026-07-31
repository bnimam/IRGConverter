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
  - [Pre-built App](#pre-built-app)
  - [Build from Source](#build-from-source)
- [Usage](#usage)
  - [Interface](#interface)
  - [Batch editing](#batch-editing)
  - [Presets](#presets)
  - [Look](#look)
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
- **Presets** — One shipped default look plus your own, saved as readable JSON. Export and import to share. See [Presets](#presets).
- **Per-control guidance** — An ⓘ button on every group explains which way to move each slider and how to tell it is wrong.
- **Sharpening** — A luminance unsharp mask with amount, radius and threshold, applied after the curves. Radius is in the exported file's pixels, and a downsampled preview says so rather than faking it. See [Sharpening](#sharpening).
- **Black and white** — From the infrared signal alone, from either visible band, or from the composite's luminance.
- **Adjustable preview resolution** — 600 px to full, so dragging stays responsive on big files.
- **Look dials** — Strength, Magenta and Density over the six group controls. A pure function of the calibration, so the same settings give the same numbers on every frame. See [Look](#look).
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

- macOS 14.0 (Sonoma) or later
- A Swift 5.9+ toolchain. Xcode is not required — Command Line Tools
  (`xcode-select --install`) is enough for `swift build`, `build_app.sh`, and
  `swift run IRGConverterCheck`.

### Pre-built App

Download `IRGConverter-1.0.0.zip` from the [releases
page](https://github.com/bnimam/IRGConverter/releases) and unzip it. Inside are the
app, the Lightroom plugin with its installer, this README, the changelog and the
licence. Move `IRGConverter.app` wherever you keep applications — `/Applications` is
where the Lightroom plugin looks first.

```bash
open IRGConverter.app
```

If the app is rejected by Gatekeeper, you may need to run:

```bash
xattr -dr com.apple.quarantine IRGConverter.app
```

### Build from Source

```bash
git clone https://github.com/bnimam/IRGConverter.git
cd IRGConverter
./build_app.sh
open IRGConverter.app
```

Or run directly via SwiftPM:

```bash
swift run
```

`./build_app.sh --zip` additionally writes `dist/IRGConverter-<version>.zip`, the
same archive the releases page carries. The version comes from one place,
`Sources/IRGConverterCore/Version.swift` — the build script reads it for the
bundle's `Info.plist` and the archive name, and `irgconvert --version` prints it.

---

## Usage

### Interface

Launch the app and either click **Open Images…** or drag files onto the preview area. Select as many as you like — they all land in the filmstrip along the bottom. Camera RAW is developed neutrally (see [Features](#features)); anything else Core Graphics can decode (JPEG, PNG, TIFF, HEIC, BMP, …) is used as-is.

Then pick a preset, or move the three **Look** dials. Everything below those is for
taste adjustments afterwards.

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
| **Look** | The three Look dials, plus IR gamma, both IR subtractions and output gamma |
| **Channels & group curves** | Source channel assignment, the red and green group curves, the output channel map, the black-and-white mode |
| **Tone, colour & curves** | Everything on the Adjust tab |
| **RAW development** | Balance, temperature, tint and headroom — skipped for a destination that is not a RAW file |

Turning a group off leaves that part of the destination photo alone, which is how
you spread a look across frames that each needed their own exposure. The four
groups partition the settings exactly: nothing belongs to two of them, and nothing
to none, so pasting everything and pasting each group in turn give the same result.
A check asserts that, and asserts one thing that is easy to get wrong — a value you
moved by hand pastes as the number you can see, not as the number the Look dials
would have produced for it.

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

| Preset | What it does |
|--------|--------------|
| **Aerochrome Magenta** | Leaves lean magenta-pink rather than pure red. Hand-tuned on a full-spectrum ORF: IR gamma 1.13, subtractions 0.50 / 0.25, output gamma 2.63, plus an S-curve on the master. |

A preset carries the three [Look](#look) dials plus everything the look does not
own — source channels, output map, black and white, photo edits. Normally it
computes the transform numbers from the dials, so each slider shows the value in
use and re-applying the look is a no-op. There is a check for that.

The default is **literal** instead: its numbers were dialled in by hand and no
combination of dials produces them — strength 0.5 would put IR gamma at the
calibrated 2.15, not 1.13, and back-solving strength from 1.13 then gives a red
subtraction of 0.16 against the 0.50 wanted. So it is marked as literal and passes
through untouched, and there is a check for *that*. Moving a Look dial still works
from there; it takes over the four controls it drives, exactly as the panel says.

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
      "name": "My Look",
      "deriveFromImage": false,
      "options": { "lookStrength": 0.5 },
      "params": { "mode": "extract", "gammaRx": 0.4, "subtractIRRed": 0.75 }
    }
  ]
}
```

### Look

Three dials over the six group controls below them:

| Dial | Range | What it moves |
|---|---|---|
| **Strength** | 0 … 1 | The infrared curve and both subtractions together — brightness and purity at once, which is what "more Aerochrome" means. |
| **Magenta** | −1 … +1 | Whether foliage reads pure red or magenta-pink, by leaving more or less infrared in the green group. |
| **Density** | −1 … +1 | Overall weight. Positive is denser and richer. |

`0.5 / 0 / 0` reproduces the calibrated look exactly. The strength range is
deliberately wide — 0 is barely converted and 1 is past tasteful, so the useful
settings sit inside rather than at the top. Measured end to end it spans **10× in
infrared gamma** and **12× in subtraction**:

| Strength | IR gamma | Red subtract | Foliage | Sky |
|---|---|---|---|---|
| 0.00 | 0.67 | 0.05 | 87,127,131 | 74,241,188 |
| 0.35 | 1.44 | 0.18 | 158,105,124 | 147,220,183 |
| 0.50 | 2.15 | 0.30 | 182,87,118 | 173,202,179 |
| 0.65 | 3.20 | 0.43 | 201,67,111 | 194,180,174 |
| 1.00 | 6.88 | 0.56 | 229,17,89 | 225,123,160 |

These are a **pure function of the dials and the calibration** — nothing is measured
from the image. That is what makes a preset mean something: the same settings give
the same numbers on every frame.

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

The root cause is worth recording, because it also explains why the two group curves
are not on a dial: `Red Group → subtract` and `Red Group → gamma` do the same job
between them. The subtraction removes most of the infrared and the curve above it,
being below 1, squashes what is left. Full analytic cancellation wants a subtraction
near `0.85`; the calibrated value is `0.30`, because the curve finishes the work.
Solving either in isolation lands nowhere near the pair that looks right.

### Controls

Once an image is loaded, the control panel on the right provides the following adjustments:

| Group | Controls | Description |
|-------|----------|-------------|
| *(tab)* | Aerochrome / Adjust | Transform controls, or ordinary photo editing. See [Adjust tab](#adjust-tab). |
| **Presets** | Choose…, Manage | The default look and your own. See [Presets](#presets). |
| **Look** | Strength, Magenta, Density | Drives the six controls below. See [Look](#look). |
| **Source Channels** | IR ←, Vis red ←, Vis green ← | Which file channel holds each signal. Defaults to IR = blue. |
| **Infrared Group** | IR gamma | Curves on the blue group. The strongest single control — it sets how red the foliage goes. |
| **Red Group** | gamma, subtract | The curve *above* the Subtract layer, and that layer's opacity. |
| **Green Group** | gamma, subtract | The curve *below* the Subtract layer, and that layer's opacity. |
| **Output** | Gamma, R ←, G ←, B ← | The final curves layer, and which signal drives each output channel. |
| **Black & White** | Off / Infrared / Visible red / Visible green / Composite luminance | Render grey instead of false colour. Unlike Solo, this is part of the image and is exported. |
| **Solo** *(checkbox on each group)* | Infrared, Red, Green | Show that one signal on its own as grey. See [Viewing aids](#viewing-aids). |
| **Show clipping** | — | Mark pixels crushed to 0 (blue) or pushed to 255 (red). |

Every control has an **ⓘ** button next to its group heading. That opens a popover
saying what the control is in the Photoshop layer stack, how to tell it is set
wrong, and which way to move it — worth more than the definition, since these
controls interact.

Gamma sliders use a logarithmic track, so 1.0 (neutral) sits at the middle
rather than being crammed against the left edge.

**Double-clicking any control** resets just that control to whatever was last
applied as a whole — the active preset, the last Look change, or the shipped
defaults. The panel says which, and each control's tooltip shows the value it
will snap back to. Resetting the one control you had nudged brings the preset
label back, since the settings match the preset again.

**Reset to Default** puts every parameter back to the default preset —
[Aerochrome Magenta](#presets), where the photo started. **Show Original** toggles
between the processed preview and the untouched source.

### Adjust tab

Everything on this tab sits *after* the Aerochrome transform, and is left alone
by the [Look](#look) dials — an edit made here survives moving them.

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
  0.944. Nothing is given up: the Look dials place the tones relative to the
  calibration, so a darker input simply needs a touch more Strength.

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
irgconvert --input P7290001.ORF --output mine.heic --preset "My Look"
irgconvert --input P7290001.ORF --output bw.heic --mono infrared --strength 0.7
irgconvert --list-presets
```

| Option | |
|---|---|
| `--input` / `--output` | Source, and destination. Always written as HEIC. |
| `--preset <name>` | Start from a named preset, the default or one of yours. Omitted, the [default preset](#presets) is used — the same starting point as the app. |
| `--strength` / `--magenta` / `--density` | The three [Look](#look) dials. They override the preset's, and take over the four controls they drive even on a literal preset. |
| `--sharpen <0..2>` / `--sharpen-radius <px>` / `--sharpen-threshold <levels>` | [Unsharp mask](#sharpening). Amount 0 is off. Full resolution here, so the radius needs no scaling. |
| `--mono <mode>` | `off`, `infrared`, `visibleRed`, `visibleGreen`, `luminance`. |
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
4. **Black and white** — Optionally flatten to grey, either from one signal or from the composite's luminance.
5. **Adjustments** — Exposure, endpoints, tonal lifts, contrast, colour tilts and saturation, in one fused pass over the three planes. Deliberately a scalar loop rather than fifteen `vDSP` passes: saturation and vibrance need all three channels of a pixel at once, the tonal masks are cheap polynomials, and one pass touches each pixel's memory once instead of fifteen times. Skipped entirely when nothing is set.
6. **Curves** — Master and per-channel curves are composed into one 256-entry table per channel and applied by interpolated table lookup, so the cost is a single lookup per channel regardless of how many control points there are.

### Verifying the maths

The vectorized pipeline is checked against a scalar transcription of the
equations above — both transforms, several parameter sets, edge cases for pure
black/white, odd image widths and row padding, plus the Look dials, the presets,
the black-and-white modes, the viewing aids, the copy/paste groups, the batch
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
- [x] Black and white mode
- [x] Adjustable preview resolution
- [x] Clickable per-control guidance
- [x] Batch processing (filmstrip, copy/paste of edits, folder export)
- [x] Histogram display
- [x] Send results back to Lightroom as 16-bit TIFFs
- [x] Sharpening (luminance unsharp mask: amount, radius, threshold)
- [ ] Waveform display
- [ ] Undo history
- [x] Infrared bleed preview to fine tune (solo + clipping viewing aids)
- [x] Double click to reset a control to the preset, the last Look change, or the default
- [x] Source channel role picker, for shooting straight off a yellow-filtered
      full-spectrum camera without pre-swapping to IRG order
- [x] Look dials (replaced the measurement-based auto button, which did not work well)
- [ ] In app instructions for fine tuning for your camera + lens + filter combo
- [x] Look Strength slider, with a range that actually spans the useful settings
- [x] Lightroom Classic plugin (sends the selection to the app)
- [x] Command-line converter
- [ ] Verify the Lightroom plugin against an actual Lightroom install

---

## License

[GNU Affero General Public License v3.0](LICENSE) — See `LICENSE` for the full text.
