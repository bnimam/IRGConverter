import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine
import IRGConverterCore

struct ContentView: View {
    /// Every photo added to the session, in strip order. Each owns its own
    /// `PhotoEdit`; the live editing state below is the current photo's copy,
    /// written back on every change.
    @State private var photos: [PhotoItem] = []
    @State private var currentID: PhotoItem.ID?
    @State private var selection: Set<PhotoItem.ID> = []

    /// Downsampled source the preview is computed from. The full-resolution image
    /// is never held: export re-develops from the URL, which also means a RAW
    /// export honours the current development settings rather than whatever was
    /// decoded at load time.
    @State private var previewInput: CGImage?
    @State private var previewOutput: CGImage?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var showOriginal = false

    /// The live editing state, seeded with the default preset so an empty window
    /// and a freshly added photo agree.
    @State private var params = PhotoEdit.default.params
    @State private var rawSettings = PhotoEdit.default.raw
    @State private var histogram: Histogram?
    /// View-only diagnostics. Never saved into a preset, never applied on export.
    @State private var aids = ViewingAids()
    @State private var tab: Tab = .aerochrome
    @State private var previewResolution = PreviewResolution.standard

    /// Copied settings, and what to call them on the photos they land on.
    @State private var copied: PhotoEdit?
    @State private var copiedFrom: String?
    @State private var pasteOptions = PasteOptions()

    @State private var batchProgress: BatchExporter.Progress?
    @State private var batchMessage: String?

    enum PreviewResolution: Int, CaseIterable, Identifiable {
        case tiny = 600
        case small = 900
        case standard = 1200
        case large = 1800
        case huge = 2600
        /// Native size. Every drag then re-renders the whole frame, so it is
        /// offered but not the default.
        case full = 0

        var id: Int { rawValue }
        var label: String { self == .full ? "Full" : "\(rawValue) px" }
        /// Nil means no limit.
        var maxDimension: Int? { self == .full ? nil : rawValue }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case aerochrome, adjust
        var id: String { rawValue }
        var label: String { self == .aerochrome ? "Aerochrome" : "Adjust" }
    }

    @State private var store = AerochromePresetStore()
    @State private var activePresetName: String?
    @State private var showSavePrompt = false
    @State private var newPresetName = ""
    @State private var statusMessage: String?
    /// Set when a preset changed the RAW development: applying it has to wait for
    /// the re-develop to finish.
    @State private var pendingPreset: AerochromePreset?
    /// Drops the results of superseded develops.
    @State private var developGeneration = 0
    /// What the current develop is decoding, so that re-entrant triggers — a photo
    /// switch also nudging `rawSettings`, say — do not decode the same file twice.
    @State private var developed: DevelopKey?
    /// True from the moment a develop starts until its result lands. Renders are
    /// pointless in between: the processor still holds the previous photo.
    @State private var isDeveloping = false

    struct DevelopKey: Equatable {
        var url: URL
        var raw: RawDevelopSettings?
        var maxDimension: Int?
    }

    /// What double-clicking a control resets it to: the last settings that were
    /// applied wholesale, which is a preset, a paste, or the shipped default.
    @State private var baseline = Baseline(edit: .default,
                                           name: AerochromePresetStore.default.name)

    struct Baseline {
        var params = PhotoEdit.default.params
        var raw = PhotoEdit.default.raw
        /// Shown in the hint and in each control's tooltip.
        var name: String?

        init(edit: PhotoEdit = .default, name: String? = nil) {
            params = edit.params
            raw = edit.raw
            self.name = name
        }

        var edit: PhotoEdit { PhotoEdit(params: params, raw: raw) }
    }

    /// Held in @State so they survive view re-initialization; plain `let`s would
    /// hand out a freshly-unprepared processor if SwiftUI ever rebuilt this value.
    @State private var engine = PreviewEngine()
    @State private var thumbs = ThumbnailEngine()
    @State private var presetPreviews = PresetPreviewEngine()

    /// The preset-tiles sheet, and the renders behind it.
    @State private var showPresetTiles = false
    @State private var presetTiles: [String: CGImage] = [:]
    @State private var isRenderingTiles = false
    @State private var exporter = BatchExporter()

    // MARK: - Current photo

    private var currentIndex: Int? { photos.index(of: currentID) }
    private var current: PhotoItem? { currentIndex.map { photos[$0] } }
    private var inputURL: URL? { current?.url }
    private var isRAW: Bool { current?.isRAW ?? false }
    private var sourceSize: PhotoItem.PixelSize? { current?.pixelSize }

    /// Selected photos in strip order — a `Set` has none, and export order should
    /// match what is on screen.
    private var selectedIDs: [PhotoItem.ID] {
        photos.map(\.id).filter { selection.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                imagePreview
                    .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320)
                controlsPanel
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
            }
            if !photos.isEmpty {
                Divider()
                batchBar
                Divider()
                Filmstrip(photos: photos,
                          currentID: $currentID,
                          selection: $selection,
                          onRemove: remove,
                          onCopy: copySettings,
                          onReveal: reveal)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear { add(urls: AppDelegate.takePending()) }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openFiles)) { note in
            guard let urls = note.userInfo?["urls"] as? [URL] else { return }
            add(urls: urls)
        }
        .onChange(of: currentID) { _, id in activate(id) }
        .onChange(of: params) { _, _ in commitEdit(); reprocess() }
        .onChange(of: rawSettings) { _, _ in commitEdit(); develop() }
        .onChange(of: aids) { _, _ in reprocess() }
        .onChange(of: previewResolution) { _, _ in develop() }
        .sheet(isPresented: $showPresetTiles) {
            PresetTilesView(
                presets: store.all,
                userPresetNames: Set(store.user.map(\.name)),
                tiles: presetTiles,
                activeName: activePresetName,
                isRendering: isRenderingTiles,
                onSelect: { preset in
                    apply(preset)
                    showPresetTiles = false
                },
                onClose: { showPresetTiles = false }
            )
        }
        .alert("Save Preset", isPresented: $showSavePrompt) {
            TextField("Name", text: $newPresetName)
            Button("Save") { savePreset(named: newPresetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current settings to your presets folder.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(photos.isEmpty ? "Open Images…" : "Add Photos…") { openImages() }

            if hasImage {
                Menu("Export") {
                    Button(isExporting ? "Exporting…" : "Save This Photo…") { saveImage() }
                        .disabled(previewOutput == nil || isExporting)
                    Divider()
                    Button("Export Selected (\(selection.count))…") {
                        exportBatch(ids: selectedIDs)
                    }
                    .disabled(selection.isEmpty || batchProgress != nil)
                    Button("Export All (\(photos.count))…") {
                        exportBatch(ids: photos.map(\.id))
                    }
                    .disabled(batchProgress != nil)
                }
                .fixedSize()

                Menu("Send to Lightroom") {
                    Button("Send This Photo") { sendToLightroom(ids: currentID.map { [$0] } ?? []) }
                        .disabled(current == nil)
                    Divider()
                    Button("Send Selected (\(selection.count))") {
                        sendToLightroom(ids: selectedIDs)
                    }
                    .disabled(selection.isEmpty)
                    Button("Send All (\(photos.count))") {
                        sendToLightroom(ids: photos.map(\.id))
                    }
                }
                .fixedSize()
                .disabled(batchProgress != nil)
                .help("Write 16-bit TIFFs beside the originals and open them in "
                      + "Lightroom. Uncompressed — about 120 MB per 20-megapixel photo.")

                Toggle("Show Original", isOn: $showOriginal)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if isExporting {
                ProgressView().controlSize(.small)
            }

            if let progress = batchProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 90)
                    Text(batchLabel(progress))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Cancel") { exporter.cancel() }
                        .controlSize(.small)
                }
            }

            Spacer()

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if let url = inputURL {
                Text(url.lastPathComponent
                     + (sourceSize.map { " · \($0.label)" } ?? "")
                     + (isRAW ? " · RAW" : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func batchLabel(_ progress: BatchExporter.Progress) -> String {
        let done = progress.completed + progress.failed
        var text = "Exporting \(min(done + 1, progress.total)) of \(progress.total)"
        if let name = progress.current { text += " · \(name)" }
        return text
    }

    // MARK: - Batch bar

    private var batchBar: some View {
        HStack(spacing: 10) {
            Button("Copy Settings") { copySettings() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(current == nil)
                .help("Copy this photo's settings, to paste onto others")

            Button(copied == nil ? "Paste" : "Paste (\(pasteOptions.summary))") {
                paste(to: selectedIDs)
            }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(copied == nil || selection.isEmpty)
                .help(copied == nil
                      ? "Copy a photo's settings first"
                      : "Paste \(pasteOptions.summary) onto the \(selection.count) "
                        + "selected photo\(selection.count == 1 ? "" : "s")")

            Menu("") {
                Button("Paste to All (\(photos.count))") { paste(to: photos.map(\.id)) }
                Divider()
                Section("Include") {
                    Toggle("Aerochrome transform", isOn: $pasteOptions.transform)
                    Toggle("Tone, colour, curves & sharpening",
                           isOn: $pasteOptions.adjustments)
                    Toggle("RAW development", isOn: $pasteOptions.rawDevelopment)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(copied == nil)
            .help("What a paste includes, and pasting to every photo")

            Divider().frame(height: 16)

            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled((currentIndex ?? 0) <= 0)

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(currentIndex == nil || currentIndex! >= photos.count - 1)

            Button("Select All") { selection = Set(photos.map(\.id)) }
                .disabled(selection.count == photos.count)

            Button("Remove") { remove(selection.isEmpty ? [] : selection) }
                .disabled(selection.isEmpty || batchProgress != nil)

            Spacer()

            if let message = batchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · "
                     + "\(selection.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Preview

    private var hasImage: Bool { previewInput != nil }

    private var displayedImage: CGImage? {
        if showOriginal { return previewInput }
        return previewOutput ?? previewInput
    }

    private var imagePreview: some View {
        Group {
            if let img = displayedImage {
                Image(img, scale: 1.0, label: Text(showOriginal ? "Original" : "Result"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Drop IRG images here\nor click Open")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topTrailing) {
            HistogramView(histogram: histogram)
        }
        .overlay(alignment: .topLeading) {
            // A soloed or clipping-marked preview is not the result. Say so, or
            // someone will export expecting what they can see.
            if aids.isActive {
                HStack(spacing: 6) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                    Text(aids.solo == .off
                         ? "Clipping overlay — not the final image"
                         : "Soloing \(aids.solo.label.lowercased()) — not the final image")
                    Button("Clear") { aids = ViewingAids() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.black)
                .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Controls

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if tab == .adjust {
                    adjustPanel
                } else {
                    aerochromePanel
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var aerochromePanel: some View {
        Group {
                presetsSection

                Divider()


                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Source Channels", info: .sourceChannels)
                    sourcePicker("IR ←", \.sourceIR)
                    sourcePicker("Vis red ←", \.sourceVisibleRed)
                    sourcePicker("Vis green ←", \.sourceVisibleGreen)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    channelHeader("Infrared Group", solo: .infrared, info: .infraredGroup)
                    slider("IR gamma", \.gammaBy, 0.1...10, logScale: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    channelHeader("Red Group", solo: .visibleRed, info: .redGroup)
                    // Gamma first, so all three groups read the same way down the
                    // panel — the infrared group has only a gamma, and the green
                    // group already listed it first.
                    slider("gamma", \.gammaRx, 0.1...10, logScale: true)
                    slider("subtract", \.subtractIRRed, 0...2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    channelHeader("Green Group", solo: .visibleGreen, info: .greenGroup)
                    slider("gamma", \.gammaGx, 0.1...10, logScale: true)
                    slider("subtract", \.subtractIRGreen, 0...2)
                }

                viewingAidsSection

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Output", info: .output)
                    slider("Gamma", \.overallGamma, 0.25...4.0, logScale: true)
                    mapPicker("Red ←", \.outputMapR)
                    mapPicker("Green ←", \.outputMapG)
                    mapPicker("Blue ←", \.outputMapB)
                }

                Divider()

                Button("Reset to Default") {
                    apply(AerochromePresetStore.default)
                }
                .buttonStyle(.bordered)
                .help("Back to “\(AerochromePresetStore.default.name)”, "
                      + "which is where every photo starts")

                Text("Double-click any control to reset it to "
                     + (baseline.name.map { "“\($0)”" } ?? "the default") + ".")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Viewing aids

    /// Section title with the solo checkbox for that signal alongside it, so the
    /// aid sits next to the controls it is there to help set.
    private func channelHeader(_ title: String, solo: ViewingAids.Solo,
                               info: SliderGuide) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            InfoButton(guide: info)
            Spacer()
            Toggle("Solo", isOn: Binding(
                get: { aids.solo == solo },
                set: { aids.solo = $0 ? solo : .off }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Show this signal on its own, in grey, with the photo edits bypassed")
        }
    }

    private func sectionHeader(_ title: String, info: SliderGuide) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            InfoButton(guide: info)
            Spacer()
        }
    }

    private var viewingAidsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Show clipping", isOn: Binding(
                get: { aids.showClipping },
                set: { aids.showClipping = $0 }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)

            if aids.showClipping {
                HStack(spacing: 10) {
                    swatch(Color(red: 0, green: 120 / 255, blue: 1), "crushed to 0")
                    swatch(Color(red: 1, green: 40 / 255, blue: 0), "pushed to 255")
                }
            }

            Text(aidsHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var aidsHint: String {
        if aids.solo != .off {
            return "Soloing \(aids.solo.label.lowercased()). Set IR Subtraction so "
                + "healthy vegetation goes nearly black in the visible channels — "
                + "leaves really do reflect almost no visible red or green. Grey "
                + "foliage means too little; large flat black areas mean too much."
        }
        return "Solo a signal above to set the subtraction and gamma by eye. In the "
            + "finished composite, infrared left in a channel and a channel "
            + "over-subtracted into nothing both just look like dark foliage."
    }

    // MARK: - Adjust tab

    @ViewBuilder
    private var adjustPanel: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Preview", info: .previewResolution)
                Picker("", selection: $previewResolution) {
                    ForEach(PreviewResolution.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text(previewResolutionNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if isRAW {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RAW Development").font(.subheadline.weight(.semibold))
                    Text("Changing these re-develops the file from the sensor data.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Neutral balance", isOn: Binding(
                        get: { rawSettings.useNeutralBalance },
                        set: { rawSettings.useNeutralBalance = $0 }
                    ))
                    .toggleStyle(.checkbox)

                    if rawSettings.useNeutralBalance {
                        Text("Channels balanced equally — the transform needs this to "
                             + "tell infrared from visible. Turn it off to set a colour "
                             + "temperature instead.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        rawSlider("Temp K", \.temperature, RawDevelopSettings.temperatureRange,
                                  format: "%.0f")
                        rawSlider("Tint", \.tint, RawDevelopSettings.tintRange, format: "%.0f")
                    }

                    rawSlider("Headroom", \.exposure, RawDevelopSettings.exposureRange)
                    Text("Stops of highlight headroom. Red clips first on a "
                         + "yellow-filtered capture; the default protects it.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tone").font(.subheadline.weight(.semibold))
                adjustSlider("Exposure", \.exposure, -3...3)
                adjustSlider("Contrast", \.contrast, -1...1)
                adjustSlider("Highlights", \.highlights, -1...1)
                adjustSlider("Shadows", \.shadows, -1...1)
                adjustSlider("Whites", \.whites, -1...1)
                adjustSlider("Blacks", \.blacks, -1...1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Colour").font(.subheadline.weight(.semibold))
                adjustSlider("Saturation", \.saturation, -1...1)
                adjustSlider("Vibrance", \.vibrance, -1...1)
                adjustSlider("Warmth", \.warmth, -1...1)
                adjustSlider("Tint", \.tint, -1...1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Curves").font(.subheadline.weight(.semibold))
                CurvesEditor(
                    curves: Binding(
                        get: { params.adjustments.curves },
                        set: { setParam(\.adjustments.curves, $0) }
                    ),
                    baseline: baseline.params.adjustments.curves,
                    histogram: histogram
                )
            }

            Divider()

            // Last in the panel because it is last in the pipeline — it amplifies
            // the edge contrast of everything above it, curves included.
            sharpeningSection

            Divider()

            Button("Reset Adjustments") {
                setParam(\.adjustments, baseline.params.adjustments)
            }
            .buttonStyle(.bordered)
            .disabled(params.adjustments == baseline.params.adjustments)

            Text("Double-click any control to reset it to "
                 + (baseline.name.map { "“\($0)”" } ?? "the default") + ".")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sharpeningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Sharpening", info: .sharpening)
            adjustSlider("Amount", (\AerochromeAdjustments.sharpening).appending(path: \.amount),
                         Sharpening.amountRange)
            adjustSlider("Radius", (\AerochromeAdjustments.sharpening).appending(path: \.radius),
                         Sharpening.radiusRange)
            adjustSlider("Threshold",
                         (\AerochromeAdjustments.sharpening).appending(path: \.threshold),
                         Sharpening.thresholdRange, format: "%.0f")
            Text(sharpeningNote)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Says what the preview is and is not showing. Sharpening is the one control
    /// whose setting is in pixels, so it is the one control a downsampled preview
    /// cannot show honestly — rather than exaggerate the radius to make it visible,
    /// the render skips it and this says so.
    private var sharpeningNote: String {
        guard params.adjustments.sharpening.amount > 0 else {
            return "Radius is in pixels of the full-size file. Amount 0 is off."
        }
        guard let effective = previewSharpeningRadius else {
            return "Radius is in pixels of the full-size file."
        }
        if effective < Sharpening.minimumVisibleRadius {
            return String(format:
                "Not shown at this preview size — %.1f px here, below the %.1f px "
                + "floor. Set Preview to Full to judge it. Export always applies it.",
                effective, Sharpening.minimumVisibleRadius)
        }
        return String(format: "Radius is in pixels of the full-size file, %.1f px "
                      + "at this preview size.", effective)
    }

    /// How much smaller the preview is than the file. Only sharpening cares — see
    /// `AerochromeProcessor.renderScale`.
    private func previewScale(of preview: CGImage) -> Float {
        guard let source = sourceSize else { return 1 }
        let native = max(source.width, source.height)
        guard native > 0 else { return 1 }
        return Float(max(preview.width, preview.height)) / Float(native)
    }

    /// The sharpening radius in the pixels the preview actually has, or nil when
    /// there is nothing on screen to measure against.
    private var previewSharpeningRadius: Float? {
        guard let preview = previewOutput ?? previewInput else { return nil }
        return params.adjustments.sharpening.radius * previewScale(of: preview)
    }

    private var previewResolutionNote: String {
        let rendered = previewOutput.map { "\($0.width)×\($0.height)" } ?? "—"
        let source = sourceSize?.label ?? "—"
        var note = "Rendering \(rendered) of \(source). Export is always full size."
        if previewResolution == .full {
            note += " At full size every slider drag re-renders the whole frame."
        }
        return note
    }

    private func adjustSlider(_ label: String,
                              _ key: WritableKeyPath<AerochromeAdjustments, Float>,
                              _ range: ClosedRange<Float>,
                              format: String = "%.2f") -> some View {
        slider(label, (\AerochromeParams.adjustments).appending(path: key), range,
               format: format)
    }

    private func rawSlider(_ label: String,
                           _ key: WritableKeyPath<RawDevelopSettings, Float>,
                           _ range: ClosedRange<Float>,
                           format: String = "%.2f") -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .frame(width: 66, alignment: .leading)
            ResettableSlider(
                value: Binding(
                    get: { Double(rawSettings[keyPath: key]) },
                    set: { rawSettings[keyPath: key] = Float($0) }
                ),
                range: Double(range.lowerBound)...Double(range.upperBound),
                onReset: { rawSettings[keyPath: key] = baseline.raw[keyPath: key] }
            )
            .frame(minWidth: 90, maxHeight: 20)
            Text(String(format: format, rawSettings[keyPath: key]))
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { rawSettings[keyPath: key] = baseline.raw[keyPath: key] }
        .help(resetHint(String(format: format, baseline.raw[keyPath: key])))
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets").font(.subheadline.weight(.semibold))
                Spacer()
                Menu("Manage") {
                    Button("Save Current Settings…") {
                        newPresetName = store.uniqueName(for: activePresetName ?? "My Preset")
                        showSavePrompt = true
                    }
                    Button("Export Current Settings…") { exportCurrentSettings() }
                    Button("Export All My Presets…") { exportUserPresets() }
                        .disabled(store.user.isEmpty)
                    Divider()
                    Button("Import Presets…") { importPresets() }
                    Button("Reveal Presets Folder") { revealPresetsFolder() }
                    if let name = activePresetName, store.user.contains(where: { $0.name == name }) {
                        Divider()
                        Button("Delete “\(name)”", role: .destructive) { deletePreset(named: name) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Menu(activePresetName ?? "Choose…") {
                Section("Built-in") {
                    ForEach(store.builtIn) { preset in
                        Button(preset.name) { apply(preset) }
                    }
                }
                if !store.user.isEmpty {
                    Section("Yours") {
                        ForEach(store.user) { preset in
                            Button(preset.name) { apply(preset) }
                        }
                    }
                }
            }

            Button("Preview Presets…") { openPresetTiles() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasImage)
                .help("See every preset applied to this photo, side by side")

            if photos.count > 1 {
                Button("Apply to Selected (\(selection.count))") {
                    applyCurrentToSelection()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selection.count < 2)
                .help("Copy this photo's settings onto every selected photo")
            }

            if let name = activePresetName,
               let notes = store.preset(named: name)?.notes {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Keep the preset label honest. It claims the current settings *are* the
    /// named preset, so it goes away when anything is edited — and comes back if
    /// the settings match again, which is exactly what happens after
    /// double-clicking the one control that had been nudged.
    private func resetHint(_ value: String) -> String {
        "Double-click to reset to \(value) (\(baseline.name ?? "default"))"
    }

    /// Record what single-control resets should revert to. Called whenever
    /// settings are applied as a whole.
    private func captureBaseline(name: String?) {
        baseline = Baseline(edit: PhotoEdit(params: params, raw: rawSettings), name: name)
    }

    private func setParam<V>(_ key: WritableKeyPath<AerochromeParams, V>, _ value: V) {
        params[keyPath: key] = value
        // The preset menu keeps naming the preset this photo was started from, even
        // once a slider has moved. It used to clear itself the moment anything
        // differed, which meant the common case — apply a preset, then adjust one control
        // for this frame — left the menu reading "Choose…" and nothing on screen said
        // where the settings came from. It is a starting point, not a claim that the
        // numbers are untouched.
        statusMessage = nil
    }

    /// One slider row bound to a parameter by key path. Double-click reverts just
    /// that control to the baseline — see `Baseline`.
    private func slider(
        _ label: String,
        _ key: WritableKeyPath<AerochromeParams, Float>,
        _ range: ClosedRange<Float>,
        logScale: Bool = false,
        format: String = "%.2f"
    ) -> some View {
        let bound = Binding(
            get: { params[keyPath: key] },
            set: { setParam(key, $0) }
        )
        return HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .frame(width: 66, alignment: .leading)
            Group {
                if logScale {
                    ResettableSlider(value: logProxy(bound, range), range: 0...1,
                                     onReset: { setParam(key, baseline.params[keyPath: key]) })
                } else {
                    ResettableSlider(
                        value: Binding(get: { Double(bound.wrappedValue) },
                                       set: { bound.wrappedValue = Float($0) }),
                        range: Double(range.lowerBound)...Double(range.upperBound),
                        onReset: { setParam(key, baseline.params[keyPath: key]) }
                    )
                }
            }
            .frame(minWidth: 90, maxHeight: 20)
            Text(String(format: format, params[keyPath: key]))
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { setParam(key, baseline.params[keyPath: key]) }
        .help(resetHint(String(format: format, baseline.params[keyPath: key])))
    }

    /// Gamma is perceptually multiplicative, so map the track logarithmically —
    /// otherwise 1.0 sits near the far left of a 0.1–10 range and everything
    /// useful is crammed into the first few pixels.
    private func logProxy(_ value: Binding<Float>, _ range: ClosedRange<Float>) -> Binding<Double> {
        let lo = log(Double(range.lowerBound))
        let hi = log(Double(range.upperBound))
        return Binding(
            get: {
                let v = Double(max(value.wrappedValue, range.lowerBound))
                return min(max((log(v) - lo) / (hi - lo), 0), 1)
            },
            set: { value.wrappedValue = Float(exp(lo + $0 * (hi - lo))) }
        )
    }

    private func mapPicker(_ label: String, _ key: WritableKeyPath<AerochromeParams, Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 66, alignment: .leading)
            Picker("", selection: Binding(
                get: { params[keyPath: key] },
                set: { setParam(key, $0) }
            )) {
                Text("Visible red").tag(0)
                Text("Visible green").tag(1)
                Text("Infrared").tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { setParam(key, baseline.params[keyPath: key]) }
    }

    private func sourcePicker(_ label: String, _ key: WritableKeyPath<AerochromeParams, Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 66, alignment: .leading)
            Picker("", selection: Binding(
                get: { params[keyPath: key] },
                set: { setParam(key, $0) }
            )) {
                Text("Red channel").tag(0)
                Text("Green channel").tag(1)
                Text("Blue channel").tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { setParam(key, baseline.params[keyPath: key]) }
    }

    // MARK: - Library

    private func openImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            add(urls: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // Each provider resolves independently and out of order, so collect them
        // and add in the order they were dropped once the last one lands.
        var resolved = [URL?](repeating: nil, count: providers.count)
        var outstanding = providers.count
        let lock = NSLock()

        for (index, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                lock.lock()
                resolved[index] = url
                outstanding -= 1
                let done = outstanding == 0
                let snapshot = resolved
                lock.unlock()
                guard done else { return }
                DispatchQueue.main.async { add(urls: snapshot.compactMap { $0 }) }
            }
        }
        return true
    }

    /// Add files to the strip, skipping any already there.
    ///
    /// New photos start from the shipped defaults rather than inheriting the
    /// current photo's edit — a batch of files from different light should not
    /// silently pick up whatever was last dialled in. Copy/paste is the explicit
    /// way to spread settings.
    private func add(urls: [URL]) {
        var seen = photos.urlKeys
        var fresh: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            fresh.append(url)
        }

        guard !fresh.isEmpty else {
            if !urls.isEmpty {
                batchMessage = urls.count == 1
                    ? "Already in the batch."
                    : "All \(urls.count) files were already in the batch."
            }
            return
        }

        errorMessage = nil
        batchMessage = fresh.count == 1
            ? "Adding \(fresh[0].lastPathComponent)…"
            : "Adding \(fresh.count) photos…"

        let wasEmpty = photos.isEmpty
        let previousCurrent = currentID
        let total = fresh.count

        // Deciding whether a file is RAW and reading its pixel size each construct
        // a `CIRAWFilter`, measured at about 100 ms per file — four seconds of dead
        // window for a forty-photo import. So probe off the main thread and append
        // each photo as it resolves: the strip fills in left to right and the first
        // photo starts developing straight away.
        DispatchQueue.global(qos: .userInitiated).async {
            for (offset, url) in fresh.enumerated() {
                let isRAW = ImageIOSupport.isRAW(url: url)
                let size = ImageIOSupport.pixelSize(of: url)
                DispatchQueue.main.async {
                    // Two rapid adds of the same file can both pass the check
                    // above before either appends, so re-check on arrival.
                    guard !photos.urlKeys.contains(url.standardizedFileURL.path) else { return }

                    let item = PhotoItem(
                        url: url,
                        isRAW: isRAW,
                        pixelSize: size.map {
                            PhotoItem.PixelSize(width: $0.width, height: $0.height)
                        }
                    )
                    photos.append(item)

                    // Newly added photos become the selection, the way an import
                    // does in a catalogue app. That is the useful default for a
                    // batch: add forty files, dial in the first, paste to the rest
                    // without selecting anything by hand.
                    if offset == 0 {
                        selection = previousCurrent.map { [$0, item.id] } ?? [item.id]
                    } else {
                        selection.insert(item.id)
                    }

                    // Only the first arrival may take focus. Testing `wasEmpty`
                    // here instead would hand it to every photo in turn and leave
                    // the *last* file of an import on screen.
                    if (wasEmpty && offset == 0) || currentID == nil {
                        currentID = item.id
                        // `onChange(of: currentID)` will call this too; it is
                        // idempotent, and calling it here starts the decode on this
                        // run loop turn rather than after the strip has laid itself
                        // out for the first time.
                        activate(item.id)
                    }

                    if offset == total - 1 {
                        batchMessage = total == 1 ? nil : "Added \(total) photos."
                    }
                    refreshThumbnail(item.id)
                }
            }
        }
    }

    private func remove(_ ids: Set<PhotoItem.ID>) {
        guard !ids.isEmpty else { return }
        let wasCurrent = currentID.map(ids.contains) ?? false
        let fallbackIndex = currentIndex ?? 0

        photos.removeAll { ids.contains($0.id) }
        for id in ids { thumbs.forget(id) }
        selection.subtract(ids)

        if photos.isEmpty {
            currentID = nil
            selection = []
            clearPreview()
            batchMessage = nil
            return
        }

        if wasCurrent {
            let next = photos[min(fallbackIndex, photos.count - 1)]
            selection.insert(next.id)
            currentID = next.id
        }
        batchMessage = "Removed \(ids.count) photo\(ids.count == 1 ? "" : "s")."
    }

    private func reveal(_ id: PhotoItem.ID) {
        guard let item = photos.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func step(_ delta: Int) {
        guard let index = currentIndex else { return }
        let next = index + delta
        guard photos.indices.contains(next) else { return }
        selection = [photos[next].id]
        currentID = photos[next].id
    }

    private func clearPreview() {
        previewInput = nil
        previewOutput = nil
        histogram = nil
        developed = nil
        isDeveloping = false
    }

    /// Make `id` the photo the panel edits: load its settings, then develop it.
    private func activate(_ id: PhotoItem.ID?) {
        guard let index = photos.index(of: id) else {
            clearPreview()
            return
        }
        let item = photos[index]
        params = item.edit.params
        rawSettings = item.edit.raw
        baseline = Baseline(edit: item.baseline, name: item.baselineName)
        activePresetName = item.presetName
        statusMessage = nil
        showOriginal = false
        pendingPreset = nil
        develop()
    }

    /// Write the live editing state back onto the current photo.
    ///
    /// Called from every settings `onChange`, which includes the ones fired by
    /// `activate` loading a photo's own values — hence the equality check, without
    /// which switching photos would queue a pointless thumbnail render each time.
    private func commitEdit() {
        guard let index = currentIndex else { return }
        let edit = PhotoEdit(params: params, raw: rawSettings)
        photos[index].baseline = baseline.edit
        photos[index].baselineName = baseline.name
        photos[index].presetName = activePresetName
        guard photos[index].edit != edit else { return }
        photos[index].edit = edit
        // The file on disk no longer matches what is on screen.
        if case .done = photos[index].exportState { photos[index].exportState = .none }
        refreshThumbnail(photos[index].id)
    }

    private func refreshThumbnail(_ id: PhotoItem.ID) {
        guard let index = photos.index(of: id) else { return }
        let item = photos[index]
        let native = item.pixelSize.map { max($0.width, $0.height) }
        thumbs.render(id: item.id, url: item.url, edit: item.edit,
                      nativeLongEdge: native) { rendered, image in
            guard let slot = photos.index(of: rendered) else { return }
            if let image {
                photos[slot].thumbnail = image
                photos[slot].thumbnailFailed = false
            } else {
                photos[slot].thumbnailFailed = true
            }
        }
    }

    // MARK: - Copy and paste

    private func copySettings() {
        guard let item = current else { return }
        copied = item.edit
        copiedFrom = item.name
        batchMessage = "Copied settings from “\(item.name)”."
    }

    private func paste(to ids: [PhotoItem.ID]) {
        guard let source = copied else { return }
        guard !pasteOptions.isEmpty else {
            batchMessage = "Nothing to paste — every group is switched off."
            return
        }
        let targets = Set(ids)
        guard !targets.isEmpty else { return }

        var changed = 0
        for index in photos.indices where targets.contains(photos[index].id) {
            let merged = pasteOptions.apply(source, to: photos[index].edit,
                                            includeRaw: photos[index].isRAW)
            guard merged != photos[index].edit else { continue }
            photos[index].edit = merged
            photos[index].baseline = merged
            photos[index].baselineName = copiedFrom.map { "pasted from \($0)" } ?? "pasted settings"
            photos[index].presetName = nil
            if case .done = photos[index].exportState { photos[index].exportState = .none }
            changed += 1
            refreshThumbnail(photos[index].id)
        }

        // The panel is showing one of the photos that just changed, so reload it.
        if let id = currentID, targets.contains(id) { activate(id) }

        batchMessage = changed == 0
            ? "Those photos already had these settings."
            : "Pasted \(pasteOptions.summary) to \(changed) photo\(changed == 1 ? "" : "s")."
    }

    /// Push the current photo's settings onto everything selected — copy and paste
    /// in one step, for the common case.
    private func applyCurrentToSelection() {
        copySettings()
        paste(to: selectedIDs)
    }

    // MARK: - Preset actions

    /// Open the tiles sheet and render it from the preview already in memory.
    ///
    /// Nothing is decoded: `previewInput` is the developed photo the preview itself
    /// is computed from, so the tiles cost one downsample plus one transform per
    /// preset.
    private func openPresetTiles() {
        guard let source = previewInput else { return }
        presetTiles = [:]
        isRenderingTiles = true
        showPresetTiles = true
        presetPreviews.render(
            source: source,
            presets: store.all,
            nativeLongEdge: sourceSize.map { max($0.width, $0.height) },
            tile: { name, image in presetTiles[name] = image },
            finished: { isRenderingTiles = false }
        )
    }

    private func apply(_ preset: AerochromePreset) {
        activePresetName = preset.name
        statusMessage = nil

        // Development settings only mean something for a RAW file; applying them
        // to a JPEG would silently do nothing and confuse the panel.
        if let raw = preset.raw, isRAW, raw != rawSettings {
            // Re-developing is asynchronous, so hand the preset off and let the
            // develop finish applying it against the new data.
            pendingPreset = preset
            rawSettings = raw
            baseline.raw = raw
            return
        }
        applyResolved(preset)
    }

    private func applyResolved(_ preset: AerochromePreset) {
        params = preset.resolved
        captureBaseline(name: preset.name)
        activePresetName = preset.name
        commitEdit()
    }

    private func currentPreset(named name: String) -> AerochromePreset {
        AerochromePreset(name: name, params: params,
                         raw: isRAW ? rawSettings : nil)
    }

    private func savePreset(named name: String) {
        do {
            let preset = currentPreset(named: store.uniqueName(for: name))
            try store.save(preset)
            activePresetName = preset.name
            statusMessage = "Saved “\(preset.name)”."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePreset(named name: String) {
        do {
            try store.delete(named: name)
            if activePresetName == name { activePresetName = nil }
            statusMessage = "Deleted “\(name)”."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCurrentSettings() {
        let name = activePresetName ?? "My Preset"
        export([currentPreset(named: name)], suggestedName: name)
    }

    private func exportUserPresets() {
        export(store.user, suggestedName: "IRGConverter Presets")
    }

    private func export(_ presets: [AerochromePreset], suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.presetContentTypes
        panel.nameFieldStringValue = "\(suggestedName).\(AerochromePresetStore.fileExtension)"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, var url = panel.url else { return }
            if url.pathExtension.isEmpty {
                url = url.appendingPathExtension(AerochromePresetStore.fileExtension)
            }
            do {
                try store.export(presets, to: url)
                statusMessage = "Exported \(presets.count) preset\(presets.count == 1 ? "" : "s")."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.presetContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            var imported: [AerochromePreset] = []
            for url in panel.urls {
                do {
                    imported += try store.importPresets(from: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            if !imported.isEmpty {
                statusMessage = "Imported " + imported.map(\.name).joined(separator: ", ") + "."
                if let first = imported.first { apply(first) }
            }
        }
    }

    private func revealPresetsFolder() {
        let dir = store.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// The custom extension is declared in the app's Info.plist; when running
    /// straight from SwiftPM there is no bundle, so fall back to plain JSON.
    private static var presetContentTypes: [UTType] {
        var types: [UTType] = []
        if let custom = UTType(filenameExtension: AerochromePresetStore.fileExtension) {
            types.append(custom)
        }
        types.append(.json)
        return types
    }

    // MARK: - Develop and render

    /// Decode the current photo at preview size.
    ///
    /// Off the main thread: a development slider drag fires this on every step, and
    /// demosaicing even a downscaled RAW takes long enough to visibly stall the UI.
    /// Stale decodes are dropped by generation, so only the newest lands.
    private func develop() {
        guard let item = current else { return }
        let key = DevelopKey(url: item.url,
                             raw: item.isRAW ? rawSettings : nil,
                             maxDimension: previewResolution.maxDimension)
        // Switching photos sets three pieces of state at once, each of which
        // triggers this; without the check the same file would be decoded three
        // times over. The in-flight test matters as much as the landed one — the
        // duplicate triggers arrive while the first decode is still running, when
        // `previewInput` is still nil.
        guard key != developed || !(isDeveloping || previewInput != nil) else { return }
        developed = key
        isDeveloping = true

        developGeneration += 1
        let generation = developGeneration
        let settings = rawSettings
        let url = item.url
        let maxDimension = previewResolution.maxDimension

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<CGImage, Error>
            do {
                // RAW decodes straight to preview size — no point demosaicing 20
                // megapixels only to throw most of it away.
                let image = try ImageIOSupport.load(url: url, raw: settings,
                                                    maxDimension: maxDimension)
                result = .success(maxDimension.map {
                    ImageIOSupport.downsample(image: image, maxDimension: $0)
                } ?? image)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard generation == developGeneration else { return }
                isDeveloping = false
                switch result {
                case .failure(let error):
                    errorMessage = error.localizedDescription
                case .success(let preview):
                    previewInput = preview
                    previewOutput = nil
                    histogram = nil
                    errorMessage = nil
                    engine.prepare(image: preview, scale: previewScale(of: preview)) { ok in
                        guard generation == developGeneration else { return }
                        guard ok else {
                            errorMessage = "Could not prepare image for processing"
                            return
                        }
                        // A preset that changed the development has to be applied
                        // against the newly developed data, not the old.
                        if let pending = pendingPreset {
                            pendingPreset = nil
                            applyResolved(pending)
                        } else {
                            reprocess()
                        }
                    }
                }
            }
        }
    }

    private func reprocess() {
        guard previewInput != nil, !isDeveloping else { return }
        engine.render(params: params, aids: aids) { image, hist in
            if let image { previewOutput = image }
            if let hist { histogram = hist }
        }
    }

    // MARK: - Export

    private func saveImage() {
        guard let item = current else { return }
        let sourceURL = item.url
        // Captured now, not read back on completion: a full-resolution export takes
        // seconds, and clicking through the filmstrip in the meantime would
        // otherwise stamp the green "exported" badge on whichever photo happened to
        // be current when the write finished.
        let photoID = item.id
        let settings = rawSettings

        let panel = NSSavePanel()
        panel.allowedContentTypes = ImageIOSupport.exportTypes
        panel.nameFieldStringValue = suggestedExportName()
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, var destination = panel.url else { return }
            // HEIC is the only format, so make the name say so however the panel
            // was left.
            if destination.pathExtension.lowercased() != ImageIOSupport.exportExtension {
                destination = destination.deletingPathExtension()
                    .appendingPathExtension(ImageIOSupport.exportExtension)
            }
            isExporting = true
            errorMessage = nil
            let snapshot = params
            // Re-develop from the file at full resolution rather than holding a
            // 20-megapixel decode in memory for the whole session. A dedicated
            // processor too: reusing the preview's instance would re-prepare it
            // at full size and leave the live preview rendering the wrong
            // dimensions behind the user's back.
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: String?
                do {
                    let source = try ImageIOSupport.load(url: sourceURL, raw: settings)
                    let exporter = AerochromeProcessor()
                    guard exporter.prepare(cgImage: source),
                          let rendered = exporter.render16(params: snapshot)
                    else { throw ImageWriteError.encodingFailed }
                    try ImageIOSupport.write(rendered, to: destination)
                } catch {
                    failure = error.localizedDescription
                }
                DispatchQueue.main.async {
                    isExporting = false
                    errorMessage = failure
                    if failure == nil, let index = photos.index(of: photoID) {
                        photos[index].exportState = .done(destination)
                    }
                }
            }
        }
    }

    private func suggestedExportName() -> String {
        let base = inputURL?.deletingPathExtension().lastPathComponent ?? "aerochrome_output"
        return "\(base)\(BatchNaming.suffix).\(ImageIOSupport.exportExtension)"
    }

    /// Convert every photo in `ids` into a folder, using each photo's own edit.
    private func exportBatch(ids: [PhotoItem.ID]) {
        guard !ids.isEmpty, batchProgress == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder for \(ids.count) converted "
            + "photo\(ids.count == 1 ? "" : "s")."
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            startBatch(ids: ids, into: .folder(directory), format: .heic, thenOpenInLightroom: false)
        }
    }

    /// Convert every photo in `ids` to 16-bit TIFF beside its original, then hand the
    /// files to Lightroom.
    ///
    /// TIFF rather than HEIC because this is a hand-off, not a finished picture:
    /// 16 bits per channel, lossless, and read natively by Lightroom. Beside the
    /// original because that is where an editor handing work to another editor is
    /// expected to leave it, and where Lightroom will show it next to the master.
    private func sendToLightroom(ids: [PhotoItem.ID]) {
        guard !ids.isEmpty, batchProgress == nil else { return }
        // Say so up front rather than after minutes of converting.
        guard LightroomBridge.isInstalled else {
            batchMessage = "Lightroom was not found on this Mac."
            return
        }
        startBatch(ids: ids, into: .besideOriginal, format: .tiff, thenOpenInLightroom: true)
    }

    private func startBatch(ids: [PhotoItem.ID],
                            into destination: BatchNaming.Destination,
                            format: ImageIOSupport.ExportFormat,
                            thenOpenInLightroom handOff: Bool) {
        let targets = Set(ids)
        var jobs: [BatchExporter.Job] = []
        for index in photos.indices where targets.contains(photos[index].id) {
            photos[index].exportState = .queued
            jobs.append(BatchExporter.Job(id: photos[index].id,
                                          url: photos[index].url,
                                          edit: photos[index].edit))
        }
        guard !jobs.isEmpty else { return }

        errorMessage = nil
        batchMessage = nil
        batchProgress = BatchExporter.Progress(completed: 0, failed: 0,
                                               total: jobs.count, current: nil)

        exporter.run(
            jobs: jobs,
            into: destination,
            format: format,
            itemStarted: { id in
                if let index = photos.index(of: id) { photos[index].exportState = .running }
            },
            itemFinished: { id, result in
                guard let index = photos.index(of: id) else { return }
                switch result {
                case .success(let url):
                    photos[index].exportState = .done(url)
                case .failure(let error):
                    photos[index].exportState = .failed(error.localizedDescription)
                }
            },
            progress: { progress in
                batchProgress = progress
            },
            finished: { progress, cancelled, written in
                batchProgress = nil
                // Anything still queued when a cancel landed never ran.
                for index in photos.indices where photos[index].exportState.isBusy {
                    photos[index].exportState = .none
                }

                let noun = handOff ? "Sent" : "Exported"
                let where_ = handOff
                    ? "beside the originals"
                    : "to " + destination.directory(for: photos.first?.url
                        ?? URL(fileURLWithPath: "/")).lastPathComponent
                var text = cancelled
                    ? "\(handOff ? "Send" : "Export") cancelled after "
                        + "\(progress.completed) of \(progress.total)."
                    : "\(noun) \(progress.completed) \(format.label) file"
                        + "\(progress.completed == 1 ? "" : "s") \(where_)."
                if progress.failed > 0 {
                    text += " \(progress.failed) failed — hover a red badge for why."
                }
                batchMessage = text

                guard handOff, !written.isEmpty else { return }
                LightroomBridge.open(written) { error in
                    if let error {
                        // The files are on disk either way, so this is a note about
                        // the hand-off, not a failed export.
                        batchMessage = text + " " + error.localizedDescription
                    } else {
                        batchMessage = text + " Opening in Lightroom…"
                    }
                }
            }
        )
    }
}
