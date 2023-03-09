//
//  ContentView.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-27.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @ObservedObject var appState: AppState
    
    // These are used just for the connection sheet
    @State var server = ""
    @State var port: Int = 8999
    @State var nick = ""
    @State var pass = ""
    @State var room = ""
    
    // The way that Syncplay handles it is to spawn this on open,
    // so let's do the same
    @State var showConnectionSheet = false
    
    @State var player = AVPlayer()
    
    // For chat and users
    @State var showInspector = false
    
    var body: some View {
        HSplitView {
            VideoPlayer(player: player)
                .onReceive(appState.$currentURL) { (newUrl) in
                    if let url = newUrl {
                        let item = AVPlayerItem(url: url)
                        player.replaceCurrentItem(with: item)
                    }
                }
                .onAppear {
                    installObservers()
                }
                .onDisappear {
                    uninstallObservers()
                }
            if showInspector {
                // TODO: Make full-height
                VStack {
                    Table(appState.users) {
                        TableColumn("Username", value: \.name)
                        TableColumn("Room", value: \.room!)
                        TableColumn("Ready") { value in
                            Text(value.ready ? "Ready" : "Not ready")
                        }
                        TableColumn("File") { value in
                            Text(value.file?.name ?? "(no file)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            // TODO: Make sure these exist in the menu bar too
            Button(action: { showInspector.toggle() }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
        //.edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showConnectionSheet, content: {
            // XXX: This is going to be pretty ugly on iOS. Makes sense to refactor into separate view.
            Spacer()
            HStack {
                Spacer()
                Form {
                    TextField("Server", text: $server)
                    TextField("Port", value: $port, formatter: NumberFormatter())
                    SecureField("Password", text: $pass)
                    TextField("Nickname", text: $nick)
                    TextField("Room", text: $room)
                    Spacer()
                    HStack{
                        Button("Connect") {
                            if appState.connect(server: server, port: port, nick: nick, room: room, pass: pass) {
                                showConnectionSheet = false
                            }
                        }
                        .keyboardShortcut(.return)
                        Button("Cancel") {
                            // XXX: Quit here
                            showConnectionSheet = false
                        }
                        .keyboardShortcut(.escape)
                    }
                }
                Spacer()
            }
            Spacer()
        })
        .onAppear {
            showConnectionSheet = true
        }
    }
    
    func installObservers() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: player.currentItem,
                                               queue: nil) { notif in
            
        }
    }
    
    func uninstallObservers() {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: nil)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appState: AppState())
    }
}
