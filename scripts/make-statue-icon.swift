// Cuts a statue out of a photo with Vision and composes it on a black macOS squircle, at exactly 1024 px.
// Usage: swift scripts/make-statue-icon.swift <source> <out.png> [keepTop=0.7] [fill=0.78] [xShift=0] [style=glow|plain|ios]
//   plain: pure black squircle, no light; ios: full-bleed opaque black square (iOS applies its own mask).
//   Also writes <out>-cutout.png: the subject alone on transparency.
//   keepTop: fraction of the cut-out subject kept from the top (drops pedestals); fill: subject height / squircle.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

let a = CommandLine.arguments
let source = CIImage(contentsOf: URL(fileURLWithPath: a[1]), options: [.applyOrientationProperty: true])!
let outURL = URL(fileURLWithPath: a[2])
let keepTop = a.count > 3 ? CGFloat(Double(a[3])!) : 0.7
let fill = a.count > 4 ? CGFloat(Double(a[4])!) : 0.78
let xShift = a.count > 5 ? CGFloat(Double(a[5])!) : 0
let style = a.count > 6 ? a[6] : "glow"

let handler = VNImageRequestHandler(ciImage: source)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject found") }
// Largest instance only, so stray people or objects in the photo are dropped.
let largest = result.allInstances.max { a, b in
    (try? result.generateScaledMaskForImage(forInstances: [a], from: handler)).map { CVPixelBufferGetWidth($0) } ?? 0 <
    (try? result.generateScaledMaskForImage(forInstances: [b], from: handler)).map { CVPixelBufferGetWidth($0) } ?? 0
}
var subject = CIImage(cvPixelBuffer: try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true))
_ = largest
let e = subject.extent
subject = subject.cropped(to: CGRect(x: e.minX, y: e.maxY - e.height * keepTop, width: e.width, height: e.height * keepTop))
subject = subject.transformed(by: .init(translationX: -subject.extent.minX, y: -subject.extent.minY))

let canvas: CGFloat = 1024
let squircle: CGFloat = style == "ios" ? 1024 : 824, inset = (canvas - squircle) / 2
let scale = squircle * fill / subject.extent.height
let resized = subject.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": scale, "inputAspectRatio": 1])
let graded = resized
    .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0, "inputContrast": 1.12, "inputBrightness": 0.02])
    .applyingFilter("CIUnsharpMask", parameters: ["inputRadius": 1.2, "inputIntensity": 0.35])
let cg = CIContext().createCGImage(graded, from: graded.extent)!
let cutoutURL = outURL.deletingPathExtension().appendingPathExtension("cutout.png")
try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: cutoutURL)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: inset, y: inset, width: squircle, height: squircle)
let radius: CGFloat = style == "ios" ? 0 : 185
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(white: 0.17, alpha: 1).cgColor, NSColor(white: 0, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
let c = CGPoint(x: canvas / 2, y: canvas * 0.62)
if style == "glow" { ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: squircle * 0.6, options: []) }
let w = CGFloat(cg.width), h = CGFloat(cg.height)
ctx.draw(cg, in: CGRect(x: (canvas - w) / 2 + xShift, y: inset, width: w, height: h))
if style == "glow" { ctx.addPath(path); ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor); ctx.setLineWidth(3); ctx.strokePath() }
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: outURL)
print("\(outURL.lastPathComponent): subject \(Int(subject.extent.width))x\(Int(subject.extent.height)) px, scale \(String(format: "%.2f", scale))x")
