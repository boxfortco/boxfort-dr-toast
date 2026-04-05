import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Renders a QR code for a URL using Core Image (no third-party deps).
struct QRCodeImage: View {
    let url: URL
    var dimension: CGFloat = 180

    var body: some View {
        Group {
            if let image = Self.makeUIImage(from: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: dimension, height: dimension)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.5))
                    .frame(width: dimension, height: dimension)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .accessibilityLabel("QR code to join this room")
    }

    private static func makeUIImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
