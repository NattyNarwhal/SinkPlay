//
//  AppState.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2022-12-28.
//

import Foundation
import SwiftUI
import NIO

class FileState : ObservableObject, CustomStringConvertible {
    @Published var name: String
    @Published var duration: TimeInterval
    @Published var size: UInt64
    
    init(name: String, duration: TimeInterval, size: UInt64) {
        self.name = name
        self.duration = duration
        self.size = size
    }
    
    public var description: String {
        "\(name) (\(duration) seconds, \(size) bytes)"
    }
}

class UserState : ObservableObject, Identifiable, CustomStringConvertible {
    let id = UUID()
    
    @Published var name: String
    // probably the wrong topology
    @Published var room: String?
    @Published var ready: Bool
    @Published var file: FileState?
    
    init(name: String, room: String?, ready: Bool, file: FileState?) {
        self.name = name
        self.room = room
        self.ready = ready
        self.file = file
    }
    
    public var description: String {
        "\(name) in room \(room) is ready (\(ready)) watching \(file)"
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
    @Published var filePosition: TimeInterval = 0
    // paused?
    
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
        users.removeAll()
        // XXX: inform UI of this
    }
    
    // Getting events from the handler
    func presentError(_ error: Error) {
        // XXX: iOS
        NSApplication.shared.presentError(error)
    }
    
    func setReady(username: String, ready: Bool) {
        users.first { user in
            user.name == username
        }?.ready = ready
        objectWillChange.send()
    }
    
    func userJoined(newUser: UserState) {
        users.removeAll(where: { user in
            user.name == newUser.name
        })
        users.append(newUser)
        objectWillChange.send()
    }
    
    func userLeft(username: String) {
        users.removeAll(where: { user in
            user.name == username
        })
        objectWillChange.send()
    }
    
    func userChangedFile(username: String, file: FileState) {
        users.first { user in
            user.name == username
        }?.file = file
        objectWillChange.send()
    }
    
    func userChangedRoom(username: String, room: String) {
        users.first { user in
            user.name == username
        }?.room = room
        objectWillChange.send()
    }
}
