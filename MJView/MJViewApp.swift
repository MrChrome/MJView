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
    weak var imageLoader: ImageLoader?
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

            Button("Paste") {
                let pasteboard = NSPasteboard.general
                guard let currentFolder = appState.imageLoader?.currentFolder else { return }

                // Handle image files from Finder
                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                    for url in urls {
                        let ext = url.pathExtension.lowercased()
                        let supportedExts = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns", "mp4", "mov", "m4v", "avi", "mkv", "flv", "webm", "mpg", "mpeg", "3gp"]
                        guard supportedExts.contains(ext) else { continue }
                        let dest = currentFolder.appendingPathComponent(url.lastPathComponent)
                        // Avoid overwriting existing files
                        var finalDest = dest
                        var counter = 1
                        while FileManager.default.fileExists(atPath: finalDest.path) {
                            let name = url.deletingPathExtension().lastPathComponent
                            finalDest = currentFolder.appendingPathComponent("\(name) \(counter).\(ext)")
                            counter += 1
                        }
                        try? FileManager.default.copyItem(at: url, to: finalDest)
                    }
                }

                // Handle images (e.g., from browser or screenshot)
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
                    for (index, image) in images.enumerated() {
                        let suffix = images.count > 1 ? " \(index + 1)" : ""
                        var dest = currentFolder.appendingPathComponent("PastedImage\(suffix).png")
                        var counter = 1
                        while FileManager.default.fileExists(atPath: dest.path) {
                            dest = currentFolder.appendingPathComponent("PastedImage\(suffix) \(counter).png")
                            counter += 1
                        }
                        if let tiffData = image.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmap.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: dest)
                        }
                    }
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(appState.imageLoader?.currentFolder == nil)
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
