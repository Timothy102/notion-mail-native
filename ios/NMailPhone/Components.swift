import MailCore
import SwiftUI

/// Letter avatar in a hairline circle (SPEC §5.13), or a photo cropped to the circle.
struct Avatar: View {
    let name: String
    var size: CGFloat = 36
    var fill: Color?
    var image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 0.5) }
        } else {
            let initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
            Circle()
                .fill(fill ?? Theme.elevated)
                .overlay { if fill == nil { Circle().strokeBorder(Theme.border, lineWidth: 1) } }
                .overlay {
                    Text(initial)
                        .font(.system(size: (size * 0.42).rounded(), weight: .medium, design: .rounded))
                        .foregroundStyle(fill == nil ? Theme.textSecondary : .white)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct LabelChip: View {
    let label: MailLabel
    var large = false

    var body: some View {
        let color = LabelColor(named: label.color)
        Text(label.name)
            .font(large ? .subheadline : .footnote)
            .lineLimit(1)
            .foregroundStyle(color.text)
            .padding(.horizontal, 6)
            .padding(.vertical, large ? 3 : 2)
            .background(color.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1 / 3)
    }
}

/// SPEC §4.8: the mailbox-and-dog drawing, a title and a message; errors drop the art and offer Retry.
struct EmptyState: View {
    var title: String
    var message: String
    var art = true
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if art {
                ZStack {
                    Image("Mailbox").resizable().foregroundStyle(Theme.textPrimary)
                    Image("DogFill").resizable().foregroundStyle(Theme.page)
                    Image("Dog").resizable().foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 200, height: 130)
                .padding(.bottom, 16)
                .accessibilityHidden(true)
            }
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.top, 4)
            if let retry {
                Button("Retry", action: retry).buttonStyle(.bordered).tint(Theme.textPrimary).padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Placeholder rows shaped like `ThreadRow`, with a highlight sweeping across them (static under Reduce Motion).
struct SkeletonRows: View {
    var count = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let widths: [(CGFloat, CGFloat, CGFloat)] = [(0.42, 0.86, 0.7), (0.34, 0.72, 0.9), (0.5, 0.9, 0.62), (0.38, 0.66, 0.8),
                                                                (0.46, 0.8, 0.74), (0.3, 0.94, 0.58), (0.4, 0.7, 0.86), (0.48, 0.76, 0.68)]

    var body: some View {
        bars
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        GeometryReader { geo in
                            let band = geo.size.width * 0.4
                            let t = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
                            LinearGradient(colors: [Theme.skeletonHighlight.opacity(0), Theme.skeletonHighlight, Theme.skeletonHighlight.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: band)
                                .offset(x: -band + (geo.size.width + band) * t)
                        }
                    }
                    .mask(bars)
                }
            }
            .accessibilityLabel("Loading mail")
    }

    private var bars: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let (sender, subject, snippet) = Self.widths[i % Self.widths.count]
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Theme.skeleton).frame(width: 36, height: 36)
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                bar(geo.size.width * sender)
                                Spacer()
                                bar(44)
                            }
                            bar(geo.size.width * subject)
                            bar(geo.size.width * snippet)
                        }
                        .padding(.top, 3)
                    }
                    .frame(height: 60)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .opacity(1 - 0.6 * Double(i) / Double(max(count, 10)))
            }
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        Capsule().fill(Theme.skeleton).frame(width: max(width, 0), height: 12)
    }
}

struct DotsLoader: View {
    @State private var up = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.textTertiary).frame(width: 5, height: 5)
                    .offset(y: up ? -2 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: up)
            }
        }
        .onAppear { up = true }
    }
}

/// Bottom toast (SPEC §5.8) above the home indicator; "Undo" runs the toast's action.
struct ToastHost: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            if let toast = app.toast {
                HStack(spacing: 16) {
                    Text(toast.text).font(.subheadline.weight(.medium)).foregroundStyle(.white).lineLimit(2)
                    Spacer(minLength: 0)
                    if let title = toast.actionTitle, let action = toast.action {
                        Button(title) {
                            action()
                            app.dismissToast(toast.id)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(0x9CC8F5, dark: 0x9CC8F5))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color(0x1D1B16, dark: 0x2F2F2F), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .padding(.horizontal, 16)
                .task(id: toast.id) {
                    try? await Task.sleep(for: toast.duration)
                    if !Task.isCancelled { app.dismissToast(toast.id) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: app.toast?.id)
    }
}

/// "Sign in with Google" per Google's branding: neutral fill, 1 pt outline, the four-colour G.
struct GoogleButton: View {
    var busy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().frame(width: 20, height: 20) } else { GoogleG().frame(width: 20, height: 20) }
                Text(busy ? "Continue in the Google sheet…" : "Sign in with Google").font(.body.weight(.medium))
            }
            .foregroundStyle(Color(0x1F1F1F, dark: 0xE3E3E3))
            .frame(maxWidth: 320, minHeight: 50)
            .background(Color(0xFFFFFF, dark: 0x131314), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(0x747775, dark: 0x8E918F), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

private struct GoogleG: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let w = d * 0.2
            ZStack {
                arc(0.125, 0.375, Color(0x34A853, dark: 0x34A853), w)
                arc(0.375, 0.53, Color(0xFBBC05, dark: 0xFBBC05), w)
                arc(0.53, 0.875, Color(0xEA4335, dark: 0xEA4335), w)
                arc(0.0, 0.125, Color(0x4285F4, dark: 0x4285F4), w)
                Rectangle().fill(Color(0x4285F4, dark: 0x4285F4)).frame(width: d * 0.46, height: w).offset(x: d * 0.21)
            }
            .frame(width: d, height: d)
        }
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color, _ width: CGFloat) -> some View {
        Circle().trim(from: from, to: to).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt)).padding(width / 2)
    }
}

/// Left-to-right wrapping layout (copy of the Mac app's), items centred within their line. With `minLastWidth`
/// the last subview (an input) stretches to fill its line and wraps when less than that is left.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?
    var minLastWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let used = frames.map(\.maxX).max() ?? 0
        let width = minLastWidth != nil ? (proposal.width ?? used) : min(proposal.width ?? used, used)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, subview) in zip(arrange(width: bounds.width, subviews: subviews), subviews) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var line: [Int] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        func closeLine() {
            for i in line { frames[i].origin.y = y + (lineHeight - frames[i].height) / 2 }
            y += lineHeight + (lineSpacing ?? spacing)
            line = []; x = 0; lineHeight = 0
        }
        for (i, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            let isStretching = minLastWidth != nil && i == subviews.count - 1
            if isStretching { size.width = minLastWidth ?? 0 }
            if !line.isEmpty, x + size.width > width { closeLine() }
            if isStretching, width.isFinite { size.width = max(width - x, size.width) }
            size.width = min(size.width, width)
            frames.append(CGRect(origin: CGPoint(x: x, y: 0), size: size))
            line.append(i)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        if !line.isEmpty { closeLine() }
        return frames
    }
}
