import SwiftUI

/// What each control does and which way to move it.
///
/// The transform's controls interact, so knowing the direction to push is worth
/// more than knowing the definition. Each entry says what the control *is* in the
/// Photoshop layer stack, how to tell it is wrong, and which way to go.
struct SliderGuide {
    let title: String
    /// What it corresponds to in the Photoshop workflow.
    let layer: String
    /// Ordered steps or symptoms — rendered as a list.
    let points: [String]

    static let sourceChannels = SliderGuide(
        title: "Source Channels",
        layer: "Splitting the image into red, green and blue groups.",
        points: [
            "A yellow-filtered full-spectrum camera puts infrared in the **blue** channel: the filter blocks visible blue, but the Bayer array passes infrared, so the blue photosites see infrared and almost nothing else.",
            "Red sees even more infrared, but mixed with visible red, which makes it useless as the reference.",
            "Set IR to **red** only if the file has already been swapped into IRG order, and move the other two along with it: vis red ← green, vis green ← blue.",
            "If foliage refuses to go red however you set the groups below, this is the first thing to check.",
        ]
    )

    static let infraredGroup = SliderGuide(
        title: "Infrared Group",
        layer: "The blue group, with a Curves adjustment on it. Above 1 brightens.",
        points: [
            "This is the single strongest control: it decides how bright infrared is, and therefore how red the foliage goes.",
            "**Tick Solo** and raise it until vegetation is bright but the histogram is not piled against the right edge.",
            "Too low and foliage comes out muddy orange or brown instead of red.",
            "Raising it also strengthens what gets subtracted from the other two groups, since both subtract *this* signal — so re-check them afterwards.",
        ]
    )

    static let redGroup = SliderGuide(
        title: "Red Group",
        layer: "Subtract layer with the infrared on top, then a Curves adjustment above it. The document starts subtract at 0.50.",
        points: [
            "**subtract** is the Subtract layer's opacity. **Tick Solo** and raise it until vegetation is nearly black — healthy leaves really do reflect almost no visible red, so that is what correct looks like.",
            "Then back off slightly. At the exact point foliage reaches black you have lost all leaf detail; tick **Show clipping** and reduce until the blue crush markers retreat off the leaves.",
            "Too little subtraction leaves foliage grey when soloed, and the finished image orange rather than red.",
            "**gamma** is the curve *above* the subtract, so it shapes what survived. Below 1 darkens. It sets how much visible-red detail — buildings, dry ground, skin — reads in the green output.",
        ]
    )

    static let greenGroup = SliderGuide(
        title: "Green Group",
        layer: "A Curves adjustment *below* the Subtract layer. The document starts subtract at 0.80.",
        points: [
            "Note the order is reversed from the red group: here the curve comes **first**, then the subtract. That is how the document builds it, and it is why the two groups behave differently.",
            "Because the curve runs first, raising **gamma** also means more survives the subtraction — it lightens the blue output twice over.",
            "**subtract** controls how magenta the foliage is. Higher pushes leaves toward pure red; lower keeps them pink.",
            "**Tick Solo** to check: vegetation should be dark but not as black as the red group, since leaves do reflect a little visible green.",
        ]
    )

    static let output = SliderGuide(
        title: "Output",
        layer: "The channel mixer on each group, plus the final Curves layer over everything.",
        points: [
            "**Gamma** is that last Curves layer. Raise it if the whole image is dark.",
            "If only the *foliage* is dark, raise IR gamma instead — this control lifts everything equally and will wash out the sky.",
            "The map is Aerochrome's false-colour shift: infrared → red, visible red → green, visible green → blue. Changing it stops the result being Aerochrome, which is occasionally what you want.",
        ]
    )

    static let previewResolution = SliderGuide(
        title: "Preview Resolution",
        layer: "How large an image the live preview is computed from.",
        points: [
            "Lower is faster to drag. Higher shows real detail and noise, which matters when judging the subtraction on fine foliage.",
            "Export is always full resolution regardless of this — it re-develops from the file.",
            "It has no effect on the settings — nothing is measured from the image, so the numbers are the same at every resolution. Sharpening is the one exception: its radius is in pixels, so a downsampled preview cannot show it.",
        ]
    )

    static let sharpening = SliderGuide(
        title: "Sharpening",
        layer: "An unsharp mask over the finished image: blur the luminance, and add back what the blur removed.",
        points: [
            "**Amount** is how much detail goes back. Past about 1.0 edges start showing a bright outline — the halo is the giveaway, not overall crispness.",
            "**Radius** is the size of detail it acts on, in pixels of the **full-size file**. Around 1 px sharpens texture; 2–3 px turns into local contrast and is usually too much for foliage.",
            "**Threshold** protects flat areas. Raise it until the sky and the shadows stop crawling — a full-spectrum capture developed with headroom has noise in both, and sharpening amplifies noise exactly as willingly as edges.",
            "It works on luminance, so it cannot shift hue. Per-channel sharpening would, and the reds here are close enough to saturation to show it.",
            "Judge it at **Preview → Full**. At smaller preview sizes the radius falls below a pixel and is skipped rather than faked, so the preview would not be telling you the truth.",
        ]
    )
}

/// A small ⓘ button that opens its guide in a popover.
struct InfoButton: View {
    let guide: SliderGuide
    @State private var shown = false

    var body: some View {
        Button {
            shown = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("How to set \(guide.title)")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(guide.title).font(.headline)
                Text(guide.layer)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                ForEach(Array(guide.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(markdown(point)).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
            .padding(14)
            .frame(width: 340)
        }
    }

    /// The guide text uses **bold** for control names; render it rather than
    /// showing the asterisks.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
