import AppKit
import SwiftUI

/// A slider that resets on double-click.
///
/// Wrapping `NSSlider` rather than using SwiftUI's `Slider` with a tap gesture:
/// `Slider` runs its own tracking loop in `mouseDown`, so whether a
/// `TapGesture(count: 2)` on it — or an `onTapGesture` on an ancestor — ever
/// sees the second click is up to SwiftUI's gesture arbitration and not
/// something worth betting the feature on. Checking `NSEvent.clickCount` in
/// `mouseDown` is unambiguous, and it is how a native control would do it.
struct ResettableSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onReset: () -> Void

    final class DoubleClickSlider: NSSlider {
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            // The first click of the pair has already been through here and moved
            // the knob; swallowing the second and resetting leaves the control at
            // the reset value either way.
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            super.mouseDown(with: event)
        }
    }

    final class Coordinator {
        var value: Binding<Double>
        var onReset: () -> Void

        init(value: Binding<Double>, onReset: @escaping () -> Void) {
            self.value = value
            self.onReset = onReset
        }

        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onReset: onReset)
    }

    func makeNSView(context: Context) -> DoubleClickSlider {
        let slider = DoubleClickSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.onDoubleClick = { context.coordinator.onReset() }
        return slider
    }

    func updateNSView(_ slider: DoubleClickSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onReset = onReset
        slider.onDoubleClick = { context.coordinator.onReset() }
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        // Skip the write while the knob is being dragged, or the round trip
        // fights the user's own movement.
        if abs(slider.doubleValue - value) > 1e-9, slider.window?.firstResponder !== slider {
            slider.doubleValue = value
        }
    }
}
