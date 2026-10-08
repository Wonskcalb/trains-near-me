import AppKit
import SNCFCore
import SwiftUI
import WidgetKit

NSTimeZone.default = TimeZone(identifier: "Europe/Paris")!
func at(_ h: Int, _ m: Int) -> Date {
    var paris = Calendar(identifier: .gregorian)
    paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    return paris.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: h, minute: m))!
}

let grenoble = Station(id: "a", name: "Grenoble", latitude: 0, longitude: 0)
let voiron = Station(id: "b", name: "Voiron", latitude: 0, longitude: 0)
let now = at(17, 40)

func train(_ h: Int, _ m: Int, _ duration: Int, delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
    TrainDeparture(scheduledDeparture: at(h, m), scheduledArrival: at(h, m).addingTimeInterval(TimeInterval(duration * 60)),
                   delayMinutes: delay, isCancelled: cancelled, trainNumber: nil)
}

let trains = [
    train(17, 42, 25), train(18, 12, 24, delay: 12), train(18, 42, 26, cancelled: true),
    train(19, 12, 25, delay: 23), train(19, 42, 25), train(20, 12, 24), train(20, 42, 26), train(21, 12, 25),
]
let normal = DeparturesEntry(date: now, fetchedAt: now, leg: Leg(from: grenoble, to: voiron), state: .departures(trains))
let noService = DeparturesEntry(date: now, fetchedAt: now, leg: Leg(from: grenoble, to: voiron), state: .noService)
let lateNight = at(23, 40)
let endOfService = DeparturesEntry(date: lateNight, fetchedAt: lateNight, leg: Leg(from: grenoble, to: voiron), state: .endOfService(firstTrain: at(5, 58).addingTimeInterval(86400)))

func size(_ family: WidgetFamily) -> CGSize {
    switch family {
    case .systemSmall: CGSize(width: 170, height: 170)
    case .systemLarge: CGSize(width: 344, height: 354)
    default: CGSize(width: 344, height: 164)
    }
}

/// Mimics the system widget chrome: content margins and the rounded container.
struct Chrome: View {
    let entry: DeparturesEntry
    let family: WidgetFamily
    var body: some View {
        DeparturesView(entry: entry, family: family)
            .frame(width: size(family).width, height: size(family).height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])

@MainActor
func png(_ view: some View, dark: Bool, _ name: String, scale: CGFloat = 2) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    appearance.performAsCurrentDrawingAppearance {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = scale
        let data = NSBitmapImageRep(data: renderer.nsImage!.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try! data.write(to: output.appendingPathComponent(name))
    }
}

struct Sheet: View {
    let dark: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Chrome(entry: normal, family: .systemSmall)
            Chrome(entry: normal, family: .systemMedium)
        }
        .padding(28)
        .background(dark ? Color(red: 0.14, green: 0.16, blue: 0.22) : Color(red: 0.80, green: 0.86, blue: 0.93))
    }
}

struct StatesSheet: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Chrome(entry: normal, family: .systemLarge)
            VStack(alignment: .leading, spacing: 20) {
                Chrome(entry: noService, family: .systemMedium)
                Chrome(entry: endOfService, family: .systemMedium)
            }
        }
        .padding(28)
        .background(Color(red: 0.80, green: 0.86, blue: 0.93))
    }
}

/// GitHub's repository social image: 1280×640.
struct SocialPreview: View {
    var body: some View {
        HStack(spacing: 56) {
            VStack(alignment: .leading, spacing: 18) {
                Image(nsImage: NSImage(contentsOf: output.appendingPathComponent("icon-board.png"))!)
                    .resizable()
                    .frame(width: 150, height: 150)
                Text("Trains near me").font(.system(size: 64, weight: .bold))
                Text("The next SNCF trains for your journey,\nright on your Mac desktop.")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 20) {
                Chrome(entry: normal, family: .systemMedium)
                Chrome(entry: endOfService, family: .systemMedium)
            }
            .scaleEffect(1.25)
        }
        .foregroundStyle(.white)
        .frame(width: 1280, height: 640)
        .background(LinearGradient(colors: [Color(red: 0.14, green: 0.16, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

MainActor.assumeIsolated {
    png(Sheet(dark: false), dark: false, "widget-light.png")
    png(Sheet(dark: true), dark: true, "widget-dark.png")
    png(StatesSheet(), dark: false, "widget-states.png")
    png(SocialPreview(), dark: true, "social-preview.png", scale: 1)
}
