import AppKit
import SwiftUI

/// A segmented control whose segments share the full width equally, however wide it is.
///
/// Not SwiftUI's `Picker(.segmented)` with `.frame(maxWidth: .infinity)`: whether that
/// stretches depends on the SDK the app is built with. Local builds stretched it, and
/// the release (built by CI against the macOS 26.5 SDK) kept it at its natural width.
/// NSSegmentedControl's `.fillEqually` does the same thing under every SDK.
struct FullWidthSegmentedControl<Value: Hashable>: NSViewRepresentable {
    let label: String
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillEqually
        // Let SwiftUI stretch it rather than hold it at the labels' width
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(label)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: FullWidthSegmentedControl

        init(_ parent: FullWidthSegmentedControl) {
            self.parent = parent
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
