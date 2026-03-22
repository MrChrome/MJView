//
//  MJViewApp.swift
//  MJView
//
//  Created by Marc Santa on 3/20/26.
//

import SwiftUI
import AppKit

enum AppearanceMode: String {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@Observable
class AppState {
    var selectedImage: ImageFile?
    var deleteTrigger: Int = 0
    var cropTrigger: Int = 0
    var currentFolderName: String = "MJView"
}

struct AppMenuCommands: Commands {
    let appState: AppState
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

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
            Button("Crop") {
                appState.cropTrigger += 1
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(appState.selectedImage == nil
                      || appState.selectedImage?.isVideo == true
                      || appState.selectedImage?.isAnimated == true
                      || appState.selectedImage?.isCloudOnly == true)
            Button("Delete") {
                appState.deleteTrigger += 1
            }
            .disabled(appState.selectedImage == nil)
        }
        CommandMenu("View") {
            Section("Appearance") {
                ForEach([AppearanceMode.system, .light, .dark], id: \.rawValue) { mode in
                    Button {
                        appearanceRaw = mode.rawValue
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if appearance == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }
}

@main
struct MJViewApp: App {
    @State private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 900, minHeight: 500)
                .preferredColorScheme(appearance.colorScheme)
                .navigationTitle(appState.currentFolderName)
        }
        .defaultSize(width: 1300, height: 700)
        .commands {
            AppMenuCommands(appState: appState)
        }
    }
}
