import Foundation

/// Diagnostic overlays for the preview. **View-only** — deliberately not part of
/// `AerochromeParams`, so they cannot be saved into a preset or leak into an
/// export.
///
/// The point of these is that the subtraction and gamma controls are otherwise
/// hard to set by eye. Looking at the finished false-colour composite, there is
/// no way to tell whether the red channel still has infrared left in it or has
/// been over-subtracted into a black hole — both look like "dark foliage". Soloing
/// the signal answers it directly: with the subtraction set correctly, healthy
/// vegetation goes nearly black in the visible channels, because healthy leaves
/// really do reflect almost no visible red or green. Too little subtraction leaves
/// them grey; too much crushes large areas flat, which the clipping overlay marks.
public struct ViewingAids: Equatable, Sendable {
    public enum Solo: String, CaseIterable, Sendable {
        case off
        case infrared
        case visibleRed
        case visibleGreen

        public var label: String {
            switch self {
            case .off: return "Off"
            case .infrared: return "Infrared"
            case .visibleRed: return "Visible red"
            case .visibleGreen: return "Visible green"
            }
        }

        /// Index into the processor's signal triple: 0 = visible red,
        /// 1 = visible green, 2 = infrared.
        var signalIndex: Int? {
            switch self {
            case .off: return nil
            case .visibleRed: return 0
            case .visibleGreen: return 1
            case .infrared: return 2
            }
        }
    }

    /// Show one signal on its own, as grey, bypassing the output channel map.
    /// The photo edits on the Adjust tab are bypassed too, so what is on screen
    /// is the signal the transform produced and nothing else.
    public var solo: Solo = .off

    /// Paint pixels that have been crushed to zero or pushed to full.
    public var showClipping = false

    public var isActive: Bool { solo != .off || showClipping }

    public init() {}

    /// Marker colours, as RGB bytes. Chosen to be obviously synthetic against a
    /// magenta-and-cyan false-colour render.
    static let crushedMarker: (r: UInt8, g: UInt8, b: UInt8) = (0, 120, 255)
    static let blownMarker: (r: UInt8, g: UInt8, b: UInt8) = (255, 40, 0)
}
