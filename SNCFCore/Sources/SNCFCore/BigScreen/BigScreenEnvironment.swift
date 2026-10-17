import os
import SwiftUI

public extension EnvironmentValues {
    /// The big-screen providers, injected at the app's scene roots (`BigScreenData.live()`). Defaults to
    /// `.fake` so previews and the screenshot build draw the mockup data. Lives in SNCFCore so the app
    /// and the widget's extra-tall view both read the same key.
    @Entry var bigScreenData: BigScreenData = .environmentDefault
}

extension BigScreenData {
    /// `.fake`, and in a Debug app build a one-time fault in the log when it is read there: a view that
    /// got the mockup in the running app sits in a presentation the live data was not passed into.
    /// Previews, the screenshot renderer and the tests carry no `SNCFAppGroup` key (or run as a preview),
    /// so they read the fake silently. A log rather than an assertion, so a missed injection never takes
    /// a debug session down.
    static var environmentDefault: BigScreenData {
        #if DEBUG
        _ = warnedAboutFake
        #endif
        return .fake
    }

    #if DEBUG
    private static let warnedAboutFake: Void = {
        let isApp = Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") != nil
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        guard isApp, !isPreview else { return }
        Logger(subsystem: "TrainsNearMe", category: "BigScreen")
            .fault("A view read the mockup BigScreenData in the app: inject \\.bigScreenData into its presentation.")
    }()
    #endif
}
