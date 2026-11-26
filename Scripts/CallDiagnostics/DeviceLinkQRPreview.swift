import SwiftUI

struct DeviceLinkQRPreview: View {
    @State var provisioningURL: InstallScreenProvisioningURL = .loaded(Self.loadedURL)

    var body: some View {
        InstallScreenQrCodeNotScannedStep(provisioningUrl: provisioningURL, retryGetQrCode: {
            provisioningURL = .loaded(Self.loadedURL)
        })
        .axoViewport()
    }
}
