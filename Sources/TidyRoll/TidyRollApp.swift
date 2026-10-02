import SwiftUI

@main
struct TidyRollApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("TidyRoll") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About TidyRoll") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About TidyRoll", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
