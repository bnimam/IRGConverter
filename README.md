# IRGConverter

> **⚠ Work in Progress** — This project is under active development. APIs, defaults, and behavior may change without notice.

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
  - [Controls](#controls)
  - [Export](#export)
- [Algorithm](#algorithm)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

This app is to recreate the Aerochrome look with a Full-spectrum digital camera. Aerochrome is a long dead
Kodak film which I believe was originally used for military and survey purposes. It's a false color film where
the blue sensitive layer is replaced with an infrared sensitive layer. By adding a yellow filter (and UV filter)
to a full spectrum converted camera, we are essentially emulatin9g the way Aerochrome captures light. With
some magic channel swapping which comes from this [JW Wong post](https://www.flickr.com/photos/jw_wong/4960099202/)
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

- **Real-time preview** — Adjust any parameter and see the result instantly on a downsampled preview.
- **Parametric controls** — Independent fraction and gamma controls for visible light and IR in each color channel.
- **Channel remapping** — Swap which processed signal feeds each output RGB channel (similar to channel mixer in Photoshop).
- **IR subtraction** — Reduce unwanted IR bleed in the red and green channels.
- **Full-resolution export** — Save as HEIC, PNG, JPEG, or TIFF at full original resolution.
- **Drag-and-drop** — Open images by dragging onto the preview pane.
- **Zero dependencies** — Pure Swift and Apple system frameworks.

---

## Installation

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (arm64)

### Pre-built App

You can download the pre-built app from the releases page.

```bash
open IRGConverter.app
```

If the app is rejected by Gatekeeper, you may need to run:

```bash
xattr -dr com.apple.quarantine IRGConverter.app
```

### Build from Source

```bash
git clone https://github.com/your-username/IRGConverter.git
cd IRGConverter
./build_app.sh
open IRGConverter.app
```

Or run directly via SwiftPM:

```bash
swift run
```

---

## Usage

### Interface

Launch the app and either click **Open IRG Image** or drag an image file onto the preview area. Supported formats include any raster image Core Graphics can decode (JPEG, PNG, TIFF, HEIC, BMP, etc.).

### Controls

Once an image is loaded, the control panel on the right provides the following adjustments:

| Group | Controls | Description |
|-------|----------|-------------|
| **Channel Mix — Red** | frac(V), γ(V), frac(IR), γ(IR) | How visible and IR light contribute to the output red channel. |
| **Channel Mix — Green** | frac(V), γ(V), frac(IR), γ(IR) | Same for the green channel. |
| **Channel Mix — Blue** | frac(V), γ(V), frac(IR), γ(IR) | Same for the blue channel. |
| **IR Subtraction** | Red, Green | Amount of IR signal subtracted from the red/green channels to remove IR bleed. |
| **Overall Gamma** | Gamma | Master gamma applied to the final output. |
| **Output Map** | R ←, G ←, B ← | Popup pickers to remap which processed signal drives each output channel. |

**Reset Defaults** restores all parameters to the starting point of the preset.

### Export

Click **Save** to export the full-resolution result. Choose between HEIC, PNG, JPEG, or TIFF. HEIC exports use a quality setting of 0.95.

---

## Algorithm

The processing pipeline operates entirely on normalized floating-point pixel buffers via Apple's Accelerate framework (vDSP).

1. **Decompose** — Split the source image into three float arrays: `R` (treated as the infrared channel), `G` (visible 1), and `B` (visible 2).
2. **Per-channel mix** — For each output channel, compute weighted combinations of visible and IR components with independent gamma adjustments.
3. **IR subtraction** — Remove cross-channel IR contamination from the red and green signals.
4. **Channel remapping** — Optionally reassign which processed signal maps to each output RGB channel.
5. **Output gamma and clamping** — Apply a final power curve and clamp to the valid range.

The processor uses a two-phase architecture: `prepare()` pre-allocates all buffers and computes invariant arrays. `process(params:)` can then be called repeatedly with different parameters without re-decomposing the source image.

---

## Roadmap

In no particular order

- [ ] Preset save/load system (~/.local/share/irgconvert)
- [ ] Batch processing
- [ ] Histogram / waveform display
- [ ] Undo history
- [ ] Progress indicator for large exports
- [ ] Infrared bleed preview to fine tune
- [ ] Double click to set slider to preset default
- [ ] In app instructrions for fine tuning for your camera + lens + filter combo

---

## License

[GNU Affero General Public License v3.0](LICENSE) — See `LICENSE` for the full text.
