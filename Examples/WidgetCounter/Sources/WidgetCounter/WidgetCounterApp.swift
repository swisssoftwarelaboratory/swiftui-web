import SwiftUI
import WidgetKit

/// A count the app and its widget share through their app group's defaults.
@main
struct WidgetCounterApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @AppStorage("count", store: UserDefaults(suiteName: "group.widgetcounter")) private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("\(count)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Button("Add one") {
                count += 1
                WidgetCenter.shared.reloadAllTimelines()
            }
            .buttonStyle(.borderedProminent)
            Text("Swipe up from the bottom to see the widget.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
