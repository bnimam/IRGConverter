import SwiftUI
import UniformTypeIdentifiers
import AppKit
import IRGConverterCore

struct ContentView: View {
    @State private var inputImage: CGImage?
    @State private var previewImage: CGImage?
    @State private var outputImage: CGImage?
    @State private var inputPath: String?
    @State private var errorMessage: String?

    @State private var params = AerochromeParams()

    private let processor = AerochromeProcessor()
    private let processQueue = DispatchQueue(label: "process", qos: .userInitiated)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                imagePreview
                    .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300)
                controlsPanel
                    .frame(minWidth: 280, maxWidth: 320)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Open IRG Image") {
                openImage()
            }

            if inputPath != nil {
                Button("Save Result") {
                    saveImage()
                }
                .disabled(outputImage == nil)
            }

            Spacer()

            if let path = inputPath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var imagePreview: some View {
        Group {
            if let img = outputImage {
                Image(img, scale: 1.0, label: Text("Result"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else if let img = inputImage {
                Image(img, scale: 1.0, label: Text("Input"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Drop an IRG image here\nor click Open")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Aerochrome Controls")
                    .font(.headline)

                groupSection("Channel Mix (Red → Full-Red)", fracX: $params.fracRx, fracY: $params.fracRy, gammaX: $params.gammaRx, gammaY: $params.gammaRy)

                groupSection("Channel Mix (Green → Full-Green)", fracX: $params.fracGx, fracY: $params.fracGy, gammaX: $params.gammaGx, gammaY: $params.gammaGy)

                groupSection("Channel Mix (Blue → Full-Blue)", fracX: $params.fracBx, fracY: $params.fracBy, gammaX: $params.gammaBx, gammaY: $params.gammaBy)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("IR Subtraction").font(.subheadline.weight(.semibold))
                    sliderRow("From Red", value: $params.subtractIRRed, range: 0...1)
                    sliderRow("From Green", value: $params.subtractIRGreen, range: 0...1)
                }

                sliderRow("Overall Gamma", value: $params.overallGamma, range: 0.2...5.0)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Channel Map").font(.subheadline.weight(.semibold))
                    mapPicker("Red ←", selection: $params.outputMapR)
                    mapPicker("Green ←", selection: $params.outputMapG)
                    mapPicker("Blue ←", selection: $params.outputMapB)
                }

                Divider()

                Button("Reset Defaults") {
                    params = AerochromeParams()
                    reprocess()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func groupSection(_ title: String, fracX: Binding<Float>, fracY: Binding<Float>, gammaX: Binding<Float>, gammaY: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            sliderRow("frac(V)", value: fracX, range: 0...1)
            sliderRow("frac(IR)", value: fracY, range: 0...1)
            sliderRow("gamma(V)", value: gammaX, range: 0.1...10)
            sliderRow("gamma(IR)", value: gammaY, range: 0.1...10)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
                .frame(width: 100)
                .onChange(of: value.wrappedValue) { _, _ in
                    reprocess()
                }
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func mapPicker(_ label: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 70, alignment: .leading)
            Picker("", selection: selection) {
                Text("Red (sub-IR)").tag(0)
                Text("Green (sub-IR)").tag(1)
                Text("Blue (IR)").tag(2)
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .onChange(of: selection.wrappedValue) { _, _ in reprocess() }
        }
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                loadImage(url: url)
            }
        }
    }

    private func saveImage() {
        guard let fullImage = inputImage else { return }
        let p = params
        DispatchQueue.global(qos: .userInitiated).async {
            let result = processor.process(cgImage: fullImage, params: p)
            DispatchQueue.main.async {
                guard let cgImage = result else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.heic, .png, .jpeg, .tiff]
                panel.nameFieldStringValue = "aerochrome_output.heic"
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        self.writeImage(cgImage, to: url)
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let item = providers.first else { return false }
        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            if let data = data as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async { loadImage(url: url) }
            }
        }
        return true
    }

    private func loadImage(url: URL) {
        guard let imageData = try? Data(contentsOf: url) else {
            errorMessage = "Could not read file"
            return
        }

        let opts: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, opts as CFDictionary),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, opts as CFDictionary)
        else {
            errorMessage = "Could not decode image"
            return
        }

        inputImage = cgImage
        previewImage = downsample(image: cgImage, maxDimension: 1200)
        inputPath = url.path
        errorMessage = nil
        if let preview = previewImage {
            processor.prepare(cgImage: preview)
            reprocess()
        }
    }

    private func downsample(image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width
        let h = image.height
        let longest = max(w, h)
        guard longest > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let newW = Int(CGFloat(w) * scale)
        let newH = Int(CGFloat(h) * scale)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: newW * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    private func reprocess() {
        let p = params
        processQueue.async {
            let result = self.processor.process(params: p)
            if let img = result {
                DispatchQueue.main.async { self.outputImage = img }
            }
        }
    }

    private func writeImage(_ cgImage: CGImage, to url: URL) {
        let ext = url.pathExtension.lowercased()

        if ext == "heic" || ext == "heif" {
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
            else { return }
            let props: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.95,
            ]
            CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
            CGImageDestinationFinalize(dest)
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData)
        else { return }

        let type: NSBitmapImageRep.FileType
        switch ext {
        case "jpg", "jpeg": type = .jpeg
        case "png": type = .png
        case "tiff", "tif": type = .tiff
        default: type = .png
        }

        let props: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.95] : [:]
        guard let data = rep.representation(using: type, properties: props) else { return }
        try? data.write(to: url)
    }
}
