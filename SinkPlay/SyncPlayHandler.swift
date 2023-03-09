//
//  SyncPlayHandler.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2023-01-01.
//

import Foundation
import NIO
import SwiftUI

class SyncPlayHandler : ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let appState: AppState
    
    private let decoder = JSONDecoder()
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func writeDictionary(dict: Dictionary<String, Any?>, context: ChannelHandlerContext) {
        // XXX: So much conversion
        if let asJson = try? JSONSerialization.data(withJSONObject: dict),
           let asJsonString = String(data: asJson, encoding: .utf8) {
            print("C->S: ", asJsonString)
            var buffer = context.channel.allocator.buffer(capacity: asJson.count + 2)
            buffer.writeString(asJsonString + "\r\n")
            context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        }
    }
    
    private func sendHello(context: ChannelHandlerContext) {
        // the official docs are misleading in what needs to be in a hello packet
        let helloMessage = [
            "Hello": [
                "username": appState.nick!,
                "room": ["name": appState.room],
                "version": "1.2.255", // ?
                "realversion": "1.7.0", // what version of syncplay we pretend to be
                "features": [
                    "sharedPlaylists": true,
                    "chat": true,
                    "uiMode": "GUI",
                    "featureList": true,
                    "readiness": true,
                    "managedRooms": true,
                    "persistentRooms": true
                ]
            ]
        ]
        writeDictionary(dict: helloMessage, context: context)
    }
    
    private func sendSetReady(context: ChannelHandlerContext) {
        let readyMessage = [
            "Set": [
                "ready": [
                    "isReady": false, // TODO: from appState
                    "manuallyInitiated": false
                ]
            ]
        ]
        writeDictionary(dict: readyMessage, context: context)
    }
    
    private func sendList(context: ChannelHandlerContext) {
        let listMessage: [String: Any?] = ["List": nil]
        writeDictionary(dict: listMessage, context: context)
    }
    
    func channelActive(context: ChannelHandlerContext) {
        sendHello(context: context)
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        print("Disconnected")
        // cleanup
        appState.disconnect()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let readableBytes = buffer.readableBytes
        if let received = buffer.readString(length: readableBytes) {
            print("C<-S: ", received)
            // XXX: We should switch the order here, so we get Data and convert to String
            // Or add JSON decode to another pipeline step
            if let data = received.data(using: .utf8) {
                self.handleJsonPayload(data: data, context: context)
            }
        }
    }
    
    // xxx: use JSON framing here...
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    // TODO: How do we handle temporary disconnects?
    // Only leave for ourselves is an explicit quit from server, IIRC?
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        DispatchQueue.main.async {
            self.appState.presentError(error)
        }
        print("Connection Error: ", error)
        context.close(promise: nil)
    }
    
    // Protocol handling
    private func handleMessageSetUser(username: String, userData: ProtocolResponse.User) {
        var file: FileState? = nil
        if let fileInfo = userData.file {
            let duration = Double(fileInfo.duration)!
            file = FileState(name: fileInfo.name, duration: duration, size: fileInfo.size)
        }
        if let event = userData.event {
            switch (event) {
            case .joined:
                // This is not the only place a user could be created, see List
                DispatchQueue.main.async {
                    let newUser = UserState(name: username, room: userData.room.name, ready: false, file: file)
                    self.appState.userJoined(newUser: newUser)
                }
            case .left:
                DispatchQueue.main.async {
                    self.appState.userLeft(username: username)
                }
            }
            return
        }
        // Now just modify existing state (only file because ready is set elsewhere)
        // TODO: Does this make sense if the user removes a file? Can they do that?
        if let file = file {
            DispatchQueue.main.async {
                self.appState.userChangedFile(username: username, file: file)
            }
        }
        // this may be a nop most of the time, but SP client lets you change rooms on the fly
        DispatchQueue.main.async {
            self.appState.userChangedRoom(username: username, room: userData.room.name)
        }
    }
    
    private func handleMessageListUser(username: String, room: String, userData: ProtocolResponse.ListUser) {
        // Maybe not best approach to treat like a join
        var file: FileState? = nil
        if let fileInfo = userData.file {
            let duration = Double(fileInfo.duration)!
            file = FileState(name: fileInfo.name, duration: duration, size: fileInfo.size)
        }
        DispatchQueue.main.async {
            let newUser = UserState(name: username, room: room, ready: userData.isReady, file: file)
            self.appState.userJoined(newUser: newUser)
        }
    }
    
    private func handleMessageSetReady(ready: ProtocolResponse.Ready) {
        DispatchQueue.main.async {
            self.appState.setReady(username: ready.username, ready: ready.isReady)
        }
    }
    
    private func handleMessageSetUsers(users: [String: ProtocolResponse.User]) {
        for (username, userData) in users {
            handleMessageSetUser(username: username, userData: userData)
        }
    }
    
    private func handleMessageState(ping: ProtocolResponse.Ping, playstate: ProtocolResponse.PlayState, context: ChannelHandlerContext) {
        var replyState: [String: Any] = [
            :
            // Not necessary to set immediately
            /*
            "playState": [
                "position": 0.0,
                "paused": true
            ]
             */
        ]
        // SyncPlay's PingService does more advanced calculation based on average RTTs
        let localTimestamp = NSDate().timeIntervalSince1970
        let ourClientLatencyCalculation = localTimestamp - ping.latencyCalculation
        replyState["ping"] = [
            "latencyCalculation": ping.latencyCalculation,
            "clientLatencyCalculation": ourClientLatencyCalculation,
            "clientRtt": 0
        ]
        // Write a state packet back, so the connection stays alive
        writeDictionary(dict: ["State": replyState], context: context)
    }
    
    private func handleJsonPayload(data: Data, context: ChannelHandlerContext) {
        do {
            let response = try decoder.decode(ProtocolResponse.self, from: data)
            switch (response) {
            case .error(let message):
                // TODO: Display it
                print("SyncPlay Protocol Error: ", message)
            case .chat(let chat):
                // TODO: Show in UI
                print(chat.username, " said ", chat.message)
            case .set(let set):
                if let user = set.user {
                    handleMessageSetUsers(users: user)
                }
                if let ready = set.ready {
                    handleMessageSetReady(ready: ready)
                }
            case .hello(let hello):
                // username
                DispatchQueue.main.async {
                    self.appState.nick = hello.username
                }
                // versions
                print("Version ", hello.version, ", Real Version", hello.realversion)
                // room
                print("Room:", hello.room.name)
                // motd
                print("MOTD:", hello.motd)
                // features
                for (fKey, fValue) in hello.features {
                    print("Feature", fKey, "=", fValue)
                }
                // Once we get a hello, we should tell the server about our readiness and ask for a list
                // world's worst state machine here
                sendSetReady(context: context)
                sendList(context: context)
            case .state(let state):
                handleMessageState(ping: state.ping, playstate: state.playstate, context: context)
            case .list(let rooms):
                for (room, users) in rooms {
                    for (user, userData) in users {
                        handleMessageListUser(username: user, room: room, userData: userData)
                    }
                }
            }
        } catch {
            dump(error)
        }
    }
}

