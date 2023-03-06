//
//  SyncPlayHandler.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2023-01-01.
//

import Foundation
import NIO
import SwiftUI

enum ProtocolResponse: Codable {
    case error(message: String)
    case chat(message: String, username: String)
    // annoying these optional values could be an enum of their own... need to figure out best way for that
    // other values: controllerAuth, newControlledRoom, room
    case set(playlistChange: PlaylistChange?, playlistIndex: PlaylistIndex?, ready: Ready?, user: [String: User]?)
    case state(ping: Ping, playstate: PlayState, ignoringOnTheFly: IgnoringOnTheFly?)
    case hello(username: String, room: Room, version: String, realversion: String, features: [String: Feature], motd: String)
    
    enum Feature: Codable {
        case int(Int)
        case bool(Bool)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else {
                throw DecodingError.typeMismatch(Feature.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Feature"))
            }
        }
    }
    
    struct Room: Codable {
        let name: String
    }
    
    struct Ping: Codable {
        let latencyCalculation: Double
        let clientLatencyCalculation: Double?
        let serverRtt: Double
    }
    
    struct PlayState: Codable {
        let position: Double
        let paused: Bool
        let doSeek: Bool
        let setBy: String?
    }
    
    struct IgnoringOnTheFly: Codable {
        let server: Int?
    }
    
    struct File: Codable {
        // only some of these may be optionals?
        let name: String
        let duration: String // convert to a double later
        let size: UInt64
    }
    
    struct User: Codable {
        let room: Room
        let event: Event?
        let file: File?
        
        /*
        struct Event: Codable {
            let joined: Bool?
            let features: [String: Feature]?
            let version: String?
            
            let left: Bool?
        }
         */
        enum Event: Codable {
            case joined//(version: String?, features: [String: Feature]?)
            case left
            
            enum CodingKeys: String, CodingKey {
                // TODO: How do we put the keys needed for version/features here?
                case joined, left//, version, features
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if (try? container.decode(Bool.self, forKey: .joined)) == true {
                    //let version = try? container.decode(String.self, forKey: .version)
                    //self = .joined(version: "", features: [:])
                    self = .joined
                } else if (try? container.decode(Bool.self, forKey: .left)) == true {
                    self = .left
                } else {
                    throw DecodingError.typeMismatch(Event.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Event"))
                }
            }
        }
    }
    
    struct PlaylistChange: Codable {
        let user: String?
        let files: [String] // XXX
    }
    
    struct PlaylistIndex: Codable {
        let user: String?
        let index: Int? // another dumb case
        
        enum CodingKeys: String, CodingKey {
            case user, index
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.user = try? container.decode(String.self, forKey: .user)
            if let x = try? container.decode(Int.self, forKey: .index) {
                self.index = x
            } else if (try? container.decode(String.self, forKey: .index)) != nil {
                self.index = nil // as the stirng indicates null somehow
            } else if try container.decodeNil(forKey: .index) {
                self.index = nil
            } else {
                throw DecodingError.typeMismatch(PlaylistIndex.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for PlaylistIndex.index"))
            }
        }
    }
    
    struct Ready: Codable {
        let isReady: Bool // either "<null>" or 0/1. awful, but we can fix that.
        let manuallyInitiated: Bool?
        let username: String
        
        enum CodingKeys: String, CodingKey {
            case isReady, manuallyInitiated, username
        }
        
        // manual because of isReady...
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.username = try! container.decode(String.self, forKey: .username)
            self.manuallyInitiated = try? container.decode(Bool.self, forKey: .manuallyInitiated)
            // now handle either case
            if let x = try? container.decode(Bool.self, forKey: .isReady) {
                self.isReady = x
            } else if (try? container.decode(String.self, forKey: .isReady)) != nil {
                self.isReady = false // as the string indicates null
            } else if try container.decodeNil(forKey: .isReady) {
                self.isReady = false
            } else {
                throw DecodingError.typeMismatch(Ready.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Ready.isReady"))
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case chat = "Chat"
        case hello = "Hello"
        case set = "Set"
        case state = "State"
    }
}

class SyncPlayHandler : ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let appState: AppState
    
    private let decoder = JSONDecoder()
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func writeDictionary(dict: Dictionary<String, Any>, context: ChannelHandlerContext) {
        // XXX: So much conversion
        if let asJson = try? JSONSerialization.data(withJSONObject: dict),
           let asJsonString = String(data: asJson, encoding: .utf8) {
            print("C->S: ", asJsonString)
            var buffer = context.channel.allocator.buffer(capacity: asJson.count + 2)
            buffer.writeString(asJsonString + "\r\n")
            context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
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
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // XXX: iOS
        NSApplication.shared.presentError(error)
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
                DispatchQueue.main.async {
                    //self.appState.userJoined(newUser: )
                }
            case .left:
                DispatchQueue.main.async {
                    self.appState.userLeft(username: username)
                }
            }
            return
        }
        // Now just modify existing state
        
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
            case .chat(message: let message, username: let username):
                // TODO: Show in UI
                print(username, " said ", message)
            case .set(playlistChange: _, playlistIndex: _, ready: let ready, user: let user):
                if let user = user {
                    handleMessageSetUsers(users: user)
                }
                if let ready = ready {
                    handleMessageSetReady(ready: ready)
                }
            case .hello(username: let username, room: let room, version: let version, realversion: let realversion, features: let features, motd: let motd):
                // username
                DispatchQueue.main.async {
                    self.appState.nick = username
                }
                // versions
                print("Version ", version, ", Real Version", realversion)
                // room
                print("Room:", room.name)
                // motd
                print("MOTD:", motd)
                // features
                for (fKey, fValue) in features {
                    print("Feature", fKey, "=", fValue)
                }
            case .state(ping: let ping, playstate: let playstate, ignoringOnTheFly: _):
                handleMessageState(ping: ping, playstate: playstate, context: context)
            }
        } catch {
            dump(error)
        }
    }
}

// SyncPlay uses JSON framing, but those frames are separated by lines
// It's not explicit, but you can tell because it uses Twisted's LineReceiver
// from https://github.com/apple/swift-nio/blob/main/Sources/NIOChatServer/main.swift
private let newLine = "\n".utf8.first!

/// Very simple example codec which will buffer inbound data until a `\n` was found.
final class LineDelimiterCodec: ByteToMessageDecoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    public var cumulationBuffer: ByteBuffer?

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        let readable = buffer.withUnsafeReadableBytes { $0.firstIndex(of: newLine) }
        if let r = readable {
            let readBytes = buffer.readSlice(length: r + 1)!
            context.fireChannelRead(self.wrapInboundOut(readBytes))
            return .continue
        }
        return .needMoreData
    }
}

