import SwiftUI

public extension EnvironmentValues {
    /// The big-screen providers, injected at the app's scene roots. Defaults to `.fake` so previews,
    /// the screenshot build and (for now) the running app all draw the mockup data; Phase 1 swaps in a
    /// live `BigScreenData` at the one injection point. Lives in SNCFCore so the app and the widget's
    /// extra-tall view both read the same key.
    @Entry var bigScreenData: BigScreenData = .fake
}
