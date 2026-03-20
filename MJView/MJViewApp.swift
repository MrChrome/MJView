//
//  MJViewApp.swift
//  MJView
//
//  Created by Marc Santa on 3/20/26.
//

import SwiftUI
import AppKit

@Observable
class AppState {
    var selectedImage: ImageFile?
    var deleteTrigger: Int = 0
}

struct EditCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                guard let url = appState.selectedImage?.url,
                      let data = try? Data(contentsOf: url),
                      let image = NSImage(data: data) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(appState.selectedImage == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete") {
                appState.deleteTrigger += 1
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(appState.selectedImage == nil)
        }
    }
}

@main
struct MJViewApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1300, height: 700)
        .commands {
            EditCommands(appState: appState)
        }
    }
}
