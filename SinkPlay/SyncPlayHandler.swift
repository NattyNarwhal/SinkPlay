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

