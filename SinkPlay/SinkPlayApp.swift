//
//  SinkPlayApp.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-27.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct SinkPlayApp: App {
    @StateObject var appState = AppState()
    
    var body: some Scene {
        // to be a singleton instead of multiple
        Window("SinkPlay", id: "SinkPlay") {
            ContentView(appState: appState)
                .onAppear {
                    // We don't want a tab bar here
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        //.windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    // XXX: iOS on ifdef, see https://stackoverflow.com/questions/56645819/how-to-open-file-dialog-with-swiftui-on-platform-uikit-for-mac
                    let picker = NSOpenPanel()
                    picker.canChooseDirectories = false
                    picker.allowsMultipleSelection = false
                    picker.allowedContentTypes = [UTType.audiovisualContent]
                    if picker.runModal() == .OK, let url = picker.url {
                        appState.currentURL = url
                    }
                }.keyboardShortcut("o")
                /*
                Button("Open URL...") {
                    
                }.keyboardShortcut("o", modifiers: [.command, .shift])
                 */
            }
            /*
            CommandMenu("Playback") {
                Button("Seek To...") {
                    
                }
                // XXX: could be on ^Z via selector?
                Button("Undo Seek") {
                    
                }
            }
             */
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
