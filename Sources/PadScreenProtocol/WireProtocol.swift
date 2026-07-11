import Foundation

public enum MessageType: UInt8, Codable, Sendable {
    case hello = 1
    case session = 2
    case codecConfiguration = 3
    case video = 4
    case input = 5
    case heartbeat = 6
    case error = 7
}

public struct WireFrame: Equatable, Sendable {
    public let type: MessageType
    public let payload: Data

    public init(type: MessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

public enum ProtocolError: Error, Equatable, Sendable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unknownMessageType(UInt8)
    case payloadTooLarge(Int)
}

public enum FrameCodec {
    public static let version: UInt8 = 1
    public static let headerSize = 12
    private static let magic: [UInt8] = [0x50, 0x44, 0x53, 0x31]

    public static func encode(_ frame: WireFrame) throws -> Data {
        guard frame.payload.count <= Int(UInt32.max) else {
            throw ProtocolError.payloadTooLarge(frame.payload.count)
        }

        var output = Data(magic)
        output.append(version)
        output.append(frame.type.rawValue)
        output.append(contentsOf: [0, 0])
        let length = UInt32(frame.payload.count)
        output.append(contentsOf: [
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ])
        output.append(frame.payload)
        return output
    }
}

public struct FrameDecoder: Sendable {
    private var buffer = Data()
    private let maxPayloadSize: Int

    public init(maxPayloadSize: Int = 16 * 1024 * 1024) {
        self.maxPayloadSize = maxPayloadSize
    }

    public mutating func append<S: Sequence>(_ bytes: S) throws -> [WireFrame] where S.Element == UInt8 {
        buffer.append(contentsOf: bytes)
        var frames: [WireFrame] = []

        while buffer.count >= FrameCodec.headerSize {
            guard Array(buffer.prefix(4)) == [0x50, 0x44, 0x53, 0x31] else {
                throw ProtocolError.invalidMagic
            }
            let version = buffer[4]
            guard version == FrameCodec.version else {
                throw ProtocolError.unsupportedVersion(version)
            }
            let rawType = buffer[5]
            guard let type = MessageType(rawValue: rawType) else {
                throw ProtocolError.unknownMessageType(rawType)
            }
            let payloadLength = (Int(buffer[8]) << 24)
                | (Int(buffer[9]) << 16)
                | (Int(buffer[10]) << 8)
                | Int(buffer[11])
            guard payloadLength <= maxPayloadSize else {
                throw ProtocolError.payloadTooLarge(payloadLength)
            }
            let frameLength = FrameCodec.headerSize + payloadLength
            guard buffer.count >= frameLength else { break }

            let payload = Data(buffer[FrameCodec.headerSize..<frameLength])
            frames.append(WireFrame(type: type, payload: payload))
            buffer = Data(buffer.dropFirst(frameLength))
        }

        return frames
    }
}

public struct HelloMessage: Codable, Equatable, Sendable {
    public let viewportWidth: Int
    public let viewportHeight: Int
    public let density: Double
    public let codecs: [String]

    public init(viewportWidth: Int, viewportHeight: Int, density: Double, codecs: [String]) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.density = density
        self.codecs = codecs
    }
}

public struct SessionMessage: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let codec: String

    public init(sessionID: UUID, width: Int, height: Int, framesPerSecond: Int, codec: String) {
        self.sessionID = sessionID
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.codec = codec
    }
}

public enum PointerAction: String, Codable, Equatable, Sendable {
    case down
    case move
    case up
    case cancel
    case scroll
}

public struct PointerMessage: Codable, Equatable, Sendable {
    public let action: PointerAction
    public let normalizedX: Double
    public let normalizedY: Double
    public let deltaX: Double
    public let deltaY: Double

    public init(action: PointerAction, normalizedX: Double, normalizedY: Double, deltaX: Double, deltaY: Double) {
        self.action = action
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public extension JSONEncoder {
    static var padScreen: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var padScreen: JSONDecoder { JSONDecoder() }
}
