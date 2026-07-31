import AppKit
import SwiftUI
import IRGConverterCore

/// The strip of photos along the bottom, plus its own toolbar.
///
/// Selection follows the Finder's rules rather than SwiftUI's list defaults:
/// plain click selects one and makes it current, ⌘-click toggles, ⇧-click extends
/// from the current photo. Modifiers are read from `NSEvent.modifierFlags` inside
/// the tap handler — the alternative, stacking `TapGesture().modifiers(…)`
/// variants, depends on gesture priority resolving the way you hoped.
struct Filmstrip: View {
    let photos: [PhotoItem]
    @Binding var currentID: PhotoItem.ID?
    @Binding var selection: Set<PhotoItem.ID>

    let onRemove: (Set<PhotoItem.ID>) -> Void
    let onCopy: () -> Void
    let onReveal: (PhotoItem.ID) -> Void

    private let thumbHeight: CGFloat = 74

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        cell(photo)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: thumbHeight + 44)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func cell(_ photo: PhotoItem) -> some View {
        let isCurrent = photo.id == currentID
        let isSelected = selection.contains(photo.id)

        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .windowBackgroundColor))

                if let thumb = photo.thumbnail {
                    Image(thumb, scale: 1.0, label: Text(photo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if photo.thumbnailFailed {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: thumbHeight * 1.5, height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(borderColor(isCurrent: isCurrent, isSelected: isSelected),
                                  lineWidth: isCurrent ? 2.5 : (isSelected ? 2 : 1))
            )
            .overlay(alignment: .topTrailing) { badge(photo) }

            Text(photo.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: thumbHeight * 1.5)
                .foregroundColor(isCurrent ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap(photo.id) }
        .help(tooltip(photo))
        .contextMenu {
            Button("Copy Settings from “\(photo.name)”") {
                if currentID != photo.id { handleTap(photo.id) }
                onCopy()
            }
            Divider()
            Button("Reveal in Finder") { onReveal(photo.id) }
            Divider()
            Button(removeTitle(photo), role: .destructive) {
                onRemove(selection.contains(photo.id) ? selection : [photo.id])
            }
        }
    }

    private func removeTitle(_ photo: PhotoItem) -> String {
        if selection.contains(photo.id), selection.count > 1 {
            return "Remove \(selection.count) Photos"
        }
        return "Remove “\(photo.name)”"
    }

    private func borderColor(isCurrent: Bool, isSelected: Bool) -> Color {
        if isCurrent { return .accentColor }
        if isSelected { return .accentColor.opacity(0.5) }
        return Color(nsColor: .separatorColor)
    }

    @ViewBuilder
    private func badge(_ photo: PhotoItem) -> some View {
        switch photo.exportState {
        case .queued:
            symbol("clock", .secondary)
        case .running:
            symbol("arrow.triangle.2.circlepath", .accentColor)
        case .done:
            symbol("checkmark.circle.fill", .green)
        case .failed:
            symbol("xmark.octagon.fill", .red)
        case .none:
            if photo.isEdited { symbol("circle.fill", .accentColor, size: 6) }
        }
    }

    private func symbol(_ name: String, _ color: Color, size: CGFloat = 10) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(color)
            .padding(2)
            .background(.black.opacity(0.45), in: Circle())
            .padding(3)
    }

    private func tooltip(_ photo: PhotoItem) -> String {
        var parts = [photo.name]
        if let size = photo.pixelSize { parts.append(size.label) }
        if photo.isRAW { parts.append("RAW") }
        switch photo.exportState {
        case .done(let url): parts.append("exported to \(url.lastPathComponent)")
        case .failed(let message): parts.append("export failed: \(message)")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    private func handleTap(_ id: PhotoItem.ID) {
        let flags = NSEvent.modifierFlags

        if flags.contains(.command) {
            // ⌘-click toggles. Never leave an empty selection: the settings panel
            // always edits *something*, so the current photo stays selected.
            if selection.contains(id), selection.count > 1 {
                selection.remove(id)
                // Hand focus to the first still-selected photo *in strip order*.
                // `selection.first` is a Set's arbitrary order, which sent the panel
                // to an unpredictable photo.
                if currentID == id {
                    currentID = photos.first { selection.contains($0.id) }?.id
                }
            } else {
                selection.insert(id)
                currentID = id
            }
            return
        }

        if flags.contains(.shift), let anchor = currentID,
           let from = photos.index(of: anchor), let to = photos.index(of: id) {
            let range = from <= to ? from...to : to...from
            selection = Set(range.map { photos[$0].id })
            currentID = id
            return
        }

        selection = [id]
        currentID = id
    }
}
