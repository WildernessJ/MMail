import SwiftUI

@main
struct MMailApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 600)
                .preferredColorScheme(model.dark ? .dark : .light)
                .environment(\.palette, model.dark ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1340, height: 860)
        .commands {
            CommandGroup(replacing: .help) {
                Button("MMail Keyboard Shortcuts") { model.help = true }
                    .keyboardShortcut("?", modifiers: [])
            }
        }
    }
}
