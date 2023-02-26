//
//  AppState.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-28.
//

import Foundation
import SwiftUI
import NIO

class UserState : ObservableObject {
    @Published var name: String
    // probably the wrong topology
    @Published var room: String
    @Published var ready: Bool
    @Published var paused: Bool
    @Published var fileName: String
    @Published var filePosition: TimeInterval
    
    init(name: String, room: String, ready: Bool, paused: Bool, fileName: String, filePosition: TimeInterval) {
        self.name = name
        self.room = room
        self.ready = ready
        self.paused = paused
        self.fileName = fileName
        self.filePosition = filePosition
    }
}

class AppState : ObservableObject {
    // variables and such
    @Published var currentURL: URL?
    
    @Published var server: String?
    @Published var port: Int = 8999
    @Published var nick: String?
    @Published var room: String?
    @Published var pass: String?
    
    @Published var users: [UserState] = []
    
    // TCP sludge
    private var chan: Channel?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    
    deinit {
        try! group.syncShutdownGracefully()
    }
    
    private var bootstrap: ClientBootstrap {
        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(LineDelimiterCodec())).flatMap { v in
                    channel.pipeline.addHandler(SyncPlayHandler(appState: self))
                }
            }
    }
    
    func connect(server: String, port: Int, nick: String, room: String, pass: String) -> Bool {
        guard !server.isEmpty else {
            return false
        }
        guard !nick.isEmpty else {
            return false
        }
        guard !room.isEmpty else {
            return false
        }
        
        self.server = server
        self.port = port
        self.nick = nick
        self.room = room
        self.pass = pass
        
        do {
            chan = try bootstrap.connect(host: server, port: port).wait()
            return true
        } catch let error {
            // XXX: iOS
            NSApplication.shared.presentError(error)
            print("Connect Error: ", error)
            return false
        }
    }
    
    func disconnect() {
        if let chan = chan {
            chan.close(mode: .all, promise: nil)
            self.chan = nil
        }
        // XXX: inform UI of this
    }
    
    // Getting events from the handler
    func setReady(username: String, ready: Bool) {
        users.first { user in
            user.name == username
        }?.ready = ready
    }
}
