@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import PadScreenProtocol

public enum RemoteInputError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case eventCreationFailed
}

public final class RemoteInputInjector: @unchecked Sendable {
    private let mapper: PointerMapper
    private var dragging = false

    public init(displayBounds: CGRect) {
        mapper = PointerMapper(displayBounds: displayBounds)
    }

    public static var isAuthorized: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func requestAuthorizationPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func inject(_ message: PointerMessage) throws {
        guard Self.isAuthorized else { throw RemoteInputError.accessibilityPermissionRequired }
        let location = try mapper.map(normalizedX: message.normalizedX, normalizedY: message.normalizedY)

        if message.action == .scroll {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(message.deltaY),
                wheel2: Int32(message.deltaX),
                wheel3: 0
            ) else { throw RemoteInputError.eventCreationFailed }
            event.post(tap: .cghidEventTap)
            return
        }

        let eventType: CGEventType
        switch message.action {
        case .down:
            dragging = true
            eventType = .leftMouseDown
        case .move:
            eventType = dragging ? .leftMouseDragged : .mouseMoved
        case .up, .cancel:
            dragging = false
            eventType = .leftMouseUp
        case .scroll:
            return
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: location, mouseButton: .left) else {
            throw RemoteInputError.eventCreationFailed
        }
        event.post(tap: .cghidEventTap)
    }
}
