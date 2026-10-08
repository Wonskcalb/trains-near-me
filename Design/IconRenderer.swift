// Renders the app icon proposals: `swift Design/IconRenderer.swift <output dir>`
import AppKit
import SwiftUI

/// Apple's macOS icon grid: 824 pt artwork centred on a 1024 pt canvas.
struct IconShell<Content: View>: View {
    let background: AnyShapeStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(background)
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 3))
                .overlay(content().frame(width: 824, height: 824).clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous)))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

let navy = Color(red: 0.07, green: 0.12, blue: 0.25)
let blue = Color(red: 0.13, green: 0.33, blue: 0.70)
let amber = Color(red: 1.00, green: 0.74, blue: 0.20)
let coral = Color(red: 0.96, green: 0.36, blue: 0.31)

/// Front view of a regional train.
struct TrainIcon: View {
    var body: some View {
        IconShell(background: AnyShapeStyle(LinearGradient(colors: [blue, navy], startPoint: .top, endPoint: .bottom))) {
            ZStack {
                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .fill(.white)
                    .frame(width: 440, height: 500)
                    .offset(y: -10)
                RoundedRectangle(cornerRadius: 50, style: .continuous)
                    .fill(navy)
                    .frame(width: 330, height: 190)
                    .offset(y: -110)
                HStack(spacing: 190) {
                    Circle().fill(amber).frame(width: 64)
                    Circle().fill(amber).frame(width: 64)
                }
                .offset(y: 120)
                Capsule().fill(navy.opacity(0.25)).frame(width: 150, height: 22).offset(y: 120)
            }
        }
    }
}

/// A tiny departure board echoing the widget's row statuses.
struct BoardIcon: View {
    func row(_ chip: Color, _ status: Color?) -> some View {
        HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(chip).frame(width: 190, height: 96)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.85)).frame(width: 230, height: 44)
            Circle().fill(status ?? .clear).frame(width: 60)
        }
        .frame(width: 600, alignment: .leading)
    }

    var body: some View {
        IconShell(background: AnyShapeStyle(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))) {
            VStack(spacing: 58) {
                row(amber, nil)
                row(amber, amber.opacity(0.9))
                row(amber.opacity(0.45), coral)
            }
        }
    }
}

/// Two rails running to the horizon, with the direction arrow.
struct TrackIcon: View {
    var body: some View {
        IconShell(background: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.10, green: 0.55, blue: 0.62), navy], startPoint: .top, endPoint: .bottom))) {
            ZStack {
                ForEach(0..<7) { i in
                    // Ties shrink and bunch up towards the horizon for perspective.
                    let t = 1 - pow(0.72, CGFloat(i))
                    let y = 824 - t * 430
                    let half = 230 - t * 190
                    Capsule().fill(.white.opacity(0.45)).frame(width: half * 2 + 60, height: 22 * (1 - t) + 6).position(x: 412, y: y)
                }
                Path { p in
                    p.move(to: CGPoint(x: 182, y: 824)); p.addLine(to: CGPoint(x: 392, y: 394))
                    p.move(to: CGPoint(x: 642, y: 824)); p.addLine(to: CGPoint(x: 432, y: 394))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                Image(systemName: "arrow.right")
                    .font(.system(size: 230, weight: .bold))
                    .foregroundStyle(amber)
                    .position(x: 412, y: 230)
            }
        }
    }
}

@MainActor
func render(_ view: some View, to url: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Design")
try MainActor.assumeIsolated {
    try render(TrainIcon(), to: out.appendingPathComponent("icon-train.png"))
    try render(BoardIcon(), to: out.appendingPathComponent("icon-board.png"))
    try render(TrackIcon(), to: out.appendingPathComponent("icon-track.png"))
}
