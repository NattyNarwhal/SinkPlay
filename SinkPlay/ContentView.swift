//
//  ContentView.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-27.
//

import SwiftUI
import AVKit

enum RightSidebarMode {
    case none
    case userList
    case chat
}

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
    @State var rightSideBar: RightSidebarMode = .none
    
    @State var messageToSend: String = ""
    
    var body: some View {
        HSplitView {
            VideoPlayer(player: player)
                .onReceive(appState.$currentURL) { (newUrl) in
                    if let url = newUrl {
                        let item = AVPlayerItem(url: url)
                        var size: UInt64? = nil
                        let path = url.path
                        if let attr = try? FileManager().attributesOfItem(atPath: path) {
                            size = attr[FileAttributeKey.size] as? UInt64
                        }
                        // https://stackoverflow.com/questions/23874574/avplayer-item-get-a-nan-duration
                        let duration = item.asset.duration.seconds
                        appState.notifyFile(name: url.lastPathComponent, duration: duration, size: size)
                        player.replaceCurrentItem(with: item)
                    }
                }
                .onAppear {
                    installObservers()
                }
                .onDisappear {
                    uninstallObservers()
                }
            if rightSideBar == .userList {
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
            } else if rightSideBar == .chat {
                VStack {
                    ScrollView {
                        // TODO: Very much the wrong way to show messages for now
                        ForEach(appState.messages) { message in
                            Text("[\(message.when)] \(message.username): \(message.message)")
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack {
                        TextField("Message", text: $messageToSend)
                        Button("Send") {
                            appState.sendChat(message: messageToSend)
                            messageToSend = ""
                            // TODO: Put focus back on the text field
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            // TODO: Make sure these exist in the menu bar too
            Button(action: { rightSideBar = (rightSideBar == .userList ? .none : .userList) }) {
                Label("Toggle Users", systemImage: "person")
            }
            Button(action: { rightSideBar = (rightSideBar == .chat ? .none : .chat) }) {
                Label("Toggle Chat", systemImage: "bubble.left.and.bubble.right")
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
