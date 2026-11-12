import SwiftUI
import WidgetKit

/// Entry point for the CapriGramIsland widget extension.
///
/// Kept separate from CapriGram's existing `WidgetExtension`. That extension
/// was built against the iOS 14 WidgetKit API and predates
/// `ActivityConfiguration`; mixing a Live Activity into it would mean
/// rebuilding the shipping widget. A second widget extension is how
/// CapriCompanion ships its island too — its `CapriWidgets` extension carries
/// `CapriLiveActivityWidget` alongside the home-screen widgets.
@main
struct CapriGramIslandBundle: WidgetBundle {
    var body: some Widget {
        CapriGramLiveActivityWidget()
    }
}
