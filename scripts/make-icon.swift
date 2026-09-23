// Renders Icon/AppIcon.icns: warm paper squircle, ink envelope, NMail's blue unread dot.
// Usage: swift scripts/make-icon.swift
import AppKit
import SwiftUI

let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
let paperTop = Color(red: 1, green: 1, blue: 1)
let paperBottom = Color(red: 0.925, green: 0.918, blue: 0.902)
let blueTop = Color(red: 0.36, green: 0.62, blue: 0.94)
let blueBottom = Color(red: 0.17, green: 0.42, blue: 0.83)

struct Envelope: Shape {
    func path(in r: CGRect) -> Path {
        let radius = r.width * 0.09
        var p = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        // The flap leaves each top corner at its arc midpoint so the joins stay smooth.
        let inset = radius * 0.29
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY + inset))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.56))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY + inset))
        return p
    }
}

/// The envelope outline with a clean gap cut around the unread dot.
struct EnvelopeWithGap: Shape {
    func path(in r: CGRect) -> Path {
        let body = CGRect(x: r.midX - 250, y: r.midY - 180 + 16, width: 500, height: 360)
        let stroke = Envelope().path(in: body)
            .strokedPath(StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
        let gap = Path(ellipseIn: CGRect(x: r.midX + 250 - 102, y: r.midY - 168 - 102, width: 204, height: 204))
        return stroke.subtracting(gap)
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [paperTop, paperBottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(.black.opacity(0.07), lineWidth: 2))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
            EnvelopeWithGap()
                .fill(ink)
                .frame(width: 1024, height: 1024)
            Circle()
                .fill(LinearGradient(colors: [blueTop, blueBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 152, height: 152)
                .offset(x: 250, y: -168)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Icon")
    let set = root.appending(path: "AppIcon.iconset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let master = root.appending(path: "AppIcon-1024.png")
    try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: master)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", set.appending(path: name).path]
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

try MainActor.assumeIsolated { try render() }
