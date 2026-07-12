import CoreGraphics
import Foundation
import PadScreenProtocol

public struct SessionRegistry: Sendable {
    public private(set) var activeClient: UUID?

    public init() {}

    @discardableResult
    public mutating func activate(_ client: UUID) -> UUID? {
        let previous = activeClient
        activeClient = client
        return previous
    }
}

public enum SessionError: Error, Equatable, Sendable {
    case noCompatibleCodec
}

public struct SessionNegotiator: Sendable {
    public init() {}

    public func negotiate(_ hello: HelloMessage) throws -> SessionMessage {
        guard hello.codecs.contains(where: { $0.caseInsensitiveCompare("h264") == .orderedSame }) else {
            throw SessionError.noCompatibleCodec
        }
        return SessionMessage(
            sessionID: UUID(),
            width: 1920,
            height: 1200,
            framesPerSecond: 90,
            codec: "h264"
        )
    }
}

public enum InputError: Error, Equatable, Sendable {
    case invalidCoordinates
}

public struct PointerMapper: Sendable {
    private let displayBounds: CGRect

    public init(displayBounds: CGRect) {
        self.displayBounds = displayBounds
    }

    public func map(normalizedX: Double, normalizedY: Double) throws -> CGPoint {
        guard normalizedX.isFinite, normalizedY.isFinite,
              (0...1).contains(normalizedX), (0...1).contains(normalizedY) else {
            throw InputError.invalidCoordinates
        }
        return CGPoint(
            x: displayBounds.minX + displayBounds.width * normalizedX,
            y: displayBounds.minY + displayBounds.height * normalizedY
        )
    }
}
