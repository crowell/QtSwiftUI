import SwiftUI

// Portable leaves for the two SignalUI controls used by CallDiagnosticWindow.
// Colors come from Serein's generated AxoColor tokens.
struct CSSText: View {
    enum Style { case titleMedium }
    let value: String
    let color: AxoColor

    init(_ value: String, type: Style, color: AxoColor) {
        self.value = value
        self.color = color
    }

    var body: some View {
        Text(verbatim: value)
            .font(.system(size: 18, weight: .semibold))
            .tracking(-0.252)
            .foregroundStyle(color)
            .frame(height: 24)
    }
}

enum AxoButton {
    enum Variant { case strongPrimary }
    enum Size { case md }

    struct Root: View {
        let label: String
        let action: () -> Void
        private var focus = AxoFocusState()

        init(_ label: String, variant: Variant, size: Size, action: @escaping () -> Void) {
            self.label = label
            self.action = action
        }

        var body: some View {
            Button(action: action) { Text(verbatim: label) }
                .buttonStyle(StrongPrimaryStyle())
                .axoFocusRing(focus.visible(autoFocus: false), in: Capsule())
                .focused(focus.$focused)
                .accessibilityIdentifier("diagnostic-close")
        }
    }

    private struct StrongPrimaryStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.039)
                .foregroundStyle(AxoColor.labelPrimaryOncolor)
                .padding(.horizontal, 12)
                .frame(minWidth: 56, minHeight: 30)
                .background { Capsule().fill(configuration.isPressed ? AxoColor.fillAccentPressed : .fillAccent) }
        }
    }
}
