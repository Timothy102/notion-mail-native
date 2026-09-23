// Renders Icon/AppIcon.icns (and Icon/AppIcon-1024.png) in the current macOS style:
// gradient squircle with a glass sheen, a solid white envelope with depth, and a warm unread dot.
// Usage: swift scripts/make-icon.swift [outDir] [blue|graphite]
import AppKit
import SwiftUI

struct Palette {
    var background: [Color]
    var envelopeTop: Color
    var envelopeBottom: Color
    var flap: Color
    var dot: [Color]
}

let palettes: [String: Palette] = [
    "blue": Palette(
        background: [Color(hex: 0x62A8FF), Color(hex: 0x2F6BFF), Color(hex: 0x5B3DF5)],
        envelopeTop: .white, envelopeBottom: Color(hex: 0xE6ECFF), flap: Color(hex: 0xD3DDFB),
        dot: [Color(hex: 0xFF9A6B), Color(hex: 0xFF4F4F)]),
    "graphite": Palette(
        background: [Color(hex: 0x3A3A3F), Color(hex: 0x1C1C1F), Color(hex: 0x0E0E10)],
        envelopeTop: .white, envelopeBottom: Color(hex: 0xE9E9EE), flap: Color(hex: 0xD6D6DD),
        dot: [Color(hex: 0x6AA8FF), Color(hex: 0x2F6BFF)]),
]

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
let envelopeSize = CGSize(width: 540, height: 390)
let dotCenter = CGPoint(x: 250, y: -170)

/// The fold: a V from the top corners down to the middle of the envelope.
struct Flap: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.56))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct Icon: View {
    let palette: Palette

    var body: some View {
        ZStack {
            squircle
                .fill(LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    // Glass sheen across the upper half.
                    squircle.fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.0)], startPoint: .top, endPoint: .center))
                )
                .overlay(
                    // Bright rim along the top edge, fading out toward the bottom.
                    squircle.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 12)

            envelope
                .offset(y: 20)

            Circle()
                .fill(LinearGradient(colors: palette.dot, startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)).padding(10))
                .overlay(Circle().strokeBorder(.white, lineWidth: 16))
                .frame(width: 176, height: 176)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .offset(x: dotCenter.x, y: dotCenter.y)
        }
        .frame(width: 1024, height: 1024)
    }

    private var envelope: some View {
        let shape = RoundedRectangle(cornerRadius: 58, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [palette.envelopeTop, palette.envelopeBottom], startPoint: .top, endPoint: .bottom))
            // The fold: a shaded triangle whose lower edges cast a soft shadow onto the body.
            Flap()
                .fill(LinearGradient(colors: [palette.flap, palette.envelopeTop], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 5)
                .clipShape(shape)
        }
        .frame(width: envelopeSize.width, height: envelopeSize.height)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
    }
}

@MainActor func render(to root: URL, palette: Palette) throws {
    let renderer = ImageRenderer(content: Icon(palette: palette))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let set = root.appending(path: "AppIcon.iconset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let master = root.appending(path: "AppIcon-1024.png")
    try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: master)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", set.appending(path: "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png").path]
            p.standardOutput = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
        }
    }
    let i = Process()
    i.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    i.arguments = ["-c", "icns", set.path, "-o", root.appending(path: "AppIcon.icns").path]
    try i.run(); i.waitUntilExit()
    try FileManager.default.removeItem(at: set)
}

let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : "Icon")
let palette = palettes[args.count > 2 ? args[2] : "blue"] ?? palettes["blue"]!
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
try MainActor.assumeIsolated { try render(to: root, palette: palette) }
