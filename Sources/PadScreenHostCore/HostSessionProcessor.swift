import Foundation
import PadScreenProtocol

public enum HostSessionError: Error, Equatable, Sendable {
    case expectedHello
    case invalidClientMessage(MessageType)
}

public struct HostSessionProcessor: Sendable {
    public private(set) var isStreaming = false
    private let negotiator: SessionNegotiator

    public init(negotiator: SessionNegotiator = SessionNegotiator()) {
        self.negotiator = negotiator
    }

    public mutating func receive(_ frame: WireFrame) throws -> [WireFrame] {
        if !isStreaming {
            guard frame.type == .hello else { throw HostSessionError.expectedHello }
            let hello = try JSONDecoder.padScreen.decode(HelloMessage.self, from: frame.payload)
            let session = try negotiator.negotiate(hello)
            isStreaming = true
            return [WireFrame(type: .session, payload: try JSONEncoder.padScreen.encode(session))]
        }

        switch frame.type {
        case .heartbeat:
            return []
        case .input:
            return []
        default:
            throw HostSessionError.invalidClientMessage(frame.type)
        }
    }
}

public final class OrderedFrameQueue<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []

    public init() {}

    public func offer(_ newValue: Element) {
        lock.withLock { values.append(newValue) }
    }

    public func take() -> Element? {
        lock.withLock {
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }
}

/// Keeps H.264 access units ordered, but catches up at an IDR boundary when the
/// network has fallen behind. Dropping the queued P-frames together and making
/// the next queued packet a keyframe avoids both an ever-growing delay and a
/// broken decoder reference chain.
public final class ReferenceSafeVideoQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let recoveryBacklogThreshold: Int
    private var values: [EncodedVideoPacket] = []
    private var droppedFrameCountStorage = 0

    public var droppedFrameCount: Int { lock.withLock { droppedFrameCountStorage } }

    public init(recoveryBacklogThreshold: Int = 8) {
        precondition(recoveryBacklogThreshold > 0)
        self.recoveryBacklogThreshold = recoveryBacklogThreshold
    }

    public func offer(_ packet: EncodedVideoPacket) {
        lock.withLock {
            if packet.isKeyFrame, values.count >= recoveryBacklogThreshold {
                droppedFrameCountStorage += values.count
                values.removeAll(keepingCapacity: true)
            }
            values.append(packet)
        }
    }

    public func take() -> EncodedVideoPacket? {
        lock.withLock {
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }
}
