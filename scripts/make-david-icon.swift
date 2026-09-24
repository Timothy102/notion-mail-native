// Cuts the subject out of Icon/source/david.png with Vision, upscales it, and composes it on a black squircle.
// Usage: swift scripts/make-david-icon.swift <outDir> [bust|head]
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "Icon/david")
let crop = args.count > 2 ? args[2] : "bust"
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let source = CIImage(contentsOf: URL(fileURLWithPath: "Icon/source/david.png"))!
let handler = VNImageRequestHandler(ciImage: source)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject found") }
let cutBuffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
var subject = CIImage(cvPixelBuffer: cutBuffer)

// "head": keep the top 68% (hair to collarbone), dropping the pedestal so the face fills the icon.
if crop == "head" {
    let e = subject.extent
    subject = subject.cropped(to: CGRect(x: e.minX, y: e.minY + e.height * 0.32, width: e.width, height: e.height * 0.68))
}

let canvas: CGFloat = 1024
let squircleSize: CGFloat = 824
let targetHeight: CGFloat = crop == "head" ? 720 : 700
let scale = targetHeight / subject.extent.height
let lanczos = CIFilter.lanczosScaleTransform()
lanczos.inputImage = subject.transformed(by: .init(translationX: -subject.extent.minX, y: -subject.extent.minY))
lanczos.scale = Float(scale)
lanczos.aspectRatio = 1
var big = lanczos.outputImage!
let sharpen = CIFilter.unsharpMask()
sharpen.inputImage = big
sharpen.radius = 2.2
sharpen.intensity = 0.55
big = sharpen.outputImage!
let lift = CIFilter.colorControls()
lift.inputImage = big
lift.contrast = 1.08
lift.brightness = 0.01
big = lift.outputImage!

let context = CIContext()
guard let cgSubject = context.createCGImage(big, from: big.extent) else { fatalError("render failed") }

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset = (canvas - squircleSize) / 2
let rect = CGRect(x: inset, y: inset, width: squircleSize, height: squircleSize)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
// Soft studio light behind the head, falling off to pure black.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(white: 0.20, alpha: 1).cgColor, NSColor(white: 0.0, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: canvas / 2, y: canvas * 0.60), startRadius: 0,
                       endCenter: CGPoint(x: canvas / 2, y: canvas * 0.60), endRadius: squircleSize * 0.62, options: [])
let w = CGFloat(cgSubject.width), h = CGFloat(cgSubject.height)
let x = (canvas - w) / 2
let y = crop == "head" ? inset - 4 : inset + (squircleSize - h) / 2 - 10
ctx.draw(cgSubject, in: CGRect(x: x, y: y, width: w, height: h))
// Hairline rim so the black squircle reads on a dark Dock.
ctx.addPath(path)
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "AppIcon-1024-\(crop).png"))
print("wrote \(out.path)/AppIcon-1024-\(crop).png (subject upscaled \(String(format: "%.1f", scale))x)")
