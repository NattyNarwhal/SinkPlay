//
//  LineDelimiterCodec.swift
//  SinkPlay
//
//  Created by Calvin Buckley on 2023-03-09.
//

import Foundation
import NIO

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
