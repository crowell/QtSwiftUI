import AppKit
import SwiftUI

private enum ComparisonError: Error { case image, dimensions, pixels }
private func pixels(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ComparisonError.image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
@main private struct Reference {
    @MainActor static func main() {
        do { try compare() } catch {
            print("Artwork comparison failed (\(error))")
            exit(1)
        }
    }
    @MainActor private static func compare() throws {
        let renderer = ImageRenderer(content: AccountArtwork().environment(\.colorScheme, .light))
        renderer.scale = 1
        let captured = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard let apple = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: apple).representation(using: .png, properties: [:]),
              let linux = NSBitmapImageRep(data: captured)?.cgImage else { throw ComparisonError.image }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard apple.width == linux.width, apple.height == linux.height else { throw ComparisonError.dimensions }
        let expected = try pixels(apple), actual = try pixels(linux)
        var different = 0, totalError = 0
        let count = apple.width * apple.height
        for pixel in 0..<count {
            var worst = 0
            for channel in 0..<3 {
                let index = 4 * pixel + channel
                let delta = abs(Int(expected[index]) - Int(actual[index]))
                worst = max(worst, delta)
                totalError += delta
            }
            if worst > 8 { different += 1 }
        }
        let percent = 100 * Double(different) / Double(count)
        print(String(format: "%d/%d pixels (%.3f%%) differ by more than 8/255 in any RGB channel. Mean channel error %.3f/255.",
                     different, count, percent, Double(totalError) / Double(3 * count)))
        guard percent <= 1 else { throw ComparisonError.pixels }
    }
}
