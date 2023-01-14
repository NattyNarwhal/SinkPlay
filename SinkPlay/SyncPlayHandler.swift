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
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func channelActive(context: ChannelHandlerContext) {
        let message = "{\"Hello\": {\"username\": \"\(appState.nick!)\", \"room\": {\"name\": \"\(appState.room!)\"}, \"version\": \"1.7.0\"}}\r\n"
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        print("C->S: ", message)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
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
                self.handleJsonPayload(data: data)
            }
        }
    }
    
    // xxx: use JSON framing here...
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        // XXX: iOS
        NSApplication.shared.presentError(error)
        print("Connection Error: ", error)
        ctx.close(promise: nil)
    }
    
    // Protocol handling
    private func handleMessageHello(hello: [String: Any]) {
        for (key, value) in hello {
            switch (key) {
            case "username":
                if let newUsername = value as? String {
                    DispatchQueue.main.async {
                        self.appState.nick = newUsername
                    }
                }
            case "version":
                // XXX: Show this to users somewhere (connection props?)
                print("Version ", value as! String)
            case "realversion":
                // XXX: Show this to users somewhere (connection props?)
                print("Real Version ", value as! String)
            case "motd":
                // XXX: Show this to users
                print("MOTD:", value as! String)
            case "room":
                if let newRoom = value as? [String: String] {
                    let newRoomName = newRoom["name"]
                    print("Room:", newRoomName)
                }
            case "features":
                // XXX: Show this to users somewhere (connection props?)
                if let features = value as? [String: Any] {
                    for (fKey, fValue) in features {
                        print("Feature", fKey, ":", fValue)
                    }
                }
            default:
                print("Unknown Hello key ", value)
            }
        }
    }
    
    private func handleMessageSet(set: [String: Any]) {
        for (key, value) in set {
            switch (key) {
            default:
                print("Unknown Set key ", value)
            }
        }
    }
    
    private func handleMessageState(state: [String: Any]) {
        for (key, value) in state {
            switch (key) {
            case "ping":
                print("Ping")
            case "playstate":
                print("State")
            default:
                print("Unknown State key ", value)
            }
        }
    }
    
    private func handleJsonPayload(data: Data) {
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            switch (json.keys.first) {
            case "Hello":
                if let hello = json.values.first! as? [String: Any] {
                    handleMessageHello(hello: hello)
                }
            case "State":
                if let state = json.values.first! as? [String: Any] {
                    handleMessageState(state: state)
                }
            case "Set":
                if let set = json.values.first! as? [String: Any] {
                    handleMessageSet(set: set)
                }
            case .none:
                print("Uh-oh, no key in the payload?")
            default:
                print("Don't know how to handle", json.keys.first!) // we checked for none earlier
            }
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

