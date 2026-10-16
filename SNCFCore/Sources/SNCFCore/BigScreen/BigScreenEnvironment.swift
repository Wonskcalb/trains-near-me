import SwiftUI

public extension EnvironmentValues {
    /// The big-screen providers, injected at the app's scene roots (`BigScreenData.live()`). Defaults to
    /// `.fake` so previews and the screenshot build draw the mockup data. Lives in SNCFCore so the app
    /// and the widget's extra-tall view both read the same key.
    @Entry var bigScreenData: BigScreenData = .fake
}
