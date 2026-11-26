import SwiftUI

struct CallSurveyPreview: View {
    private enum Detail { case diagnostics, debugLog }
    @State private var detail: Detail?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.i18n) private var i18n

    var body: some View {
        AxoBaseDialog.Host {
            CallQualitySurveyDialog(onClose: { dismiss() }, onSubmit: { _ in dismiss() },
                                    onViewDebugLog: { detail = .debugLog }, onViewDiagnosticInfo: { detail = .diagnostics })
        }
        .background(AxoColor.surfacePrimary)
        .overlay {
            switch detail {
            case .diagnostics:
                CallDiagnosticWindow(diagnosticData: DiagnosticContent.report) { detail = nil }
            case .debugLog:
                VStack(alignment: .leading, spacing: 16) {
                    CSSText(i18n("icu:submitDebugLog"), type: .titleMedium)
                    ScrollView {
                        Text(verbatim: "Sample log\nCall connected\nAudio device changed\nCall ended")
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    AxoButton.Root(i18n("icu:close"), variant: .strongPrimary, size: .md) { detail = nil }
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AxoColor.surfacePrimary).onExitCommand { detail = nil }
            case nil: EmptyView()
            }
        }
    }
}
