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
