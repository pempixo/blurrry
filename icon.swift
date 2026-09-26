import AppKit
import CoreImage

// Renders the background layer of blurrry's app icon (AppIcon.icon): a dark, softly blurred field.
// The window on top is a vector glass layer that macOS renders in 3D.
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func ctx() -> CGContext { CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }

let field = ctx()
field.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)); field.fill(CGRect(x: 0, y: 0, width: S, height: S))
for (x, y, r, c) in [(300.0, 700.0, 280.0, (0.30, 0.32, 0.42)), (740.0, 300.0, 300.0, (0.24, 0.30, 0.34)), (760.0, 780.0, 200.0, (0.36, 0.30, 0.38))] {
    field.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.95))
    field.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
let blurredCI = CIImage(cgImage: field.makeImage()!).clampedToExtent().applyingGaussianBlur(sigma: 100).cropped(to: CGRect(x: 0, y: 0, width: S, height: S))
let blurred = CIContext().createCGImage(blurredCI, from: blurredCI.extent)!

let rep = NSBitmapImageRep(cgImage: blurred)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
