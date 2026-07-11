import CoreGraphics
import VirtualDisplayBridge

public enum VirtualDisplayError: Error, Equatable, Sendable {
    case invalidConfiguration
    case privateAPIUnavailable
    case creationFailed
    case settingsRejected
}

public struct VirtualDisplayConfiguration: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double

    public init(width: Int = 1920, height: Int = 1200, refreshRate: Double = 120) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
    }

    public func validate() throws {
        guard width > 0, height > 0, refreshRate.isFinite, refreshRate > 0 else {
            throw VirtualDisplayError.invalidConfiguration
        }
    }
}

public protocol VirtualDisplayProviding: AnyObject {
    var displayID: CGDirectDisplayID { get }
}

public final class CoreGraphicsVirtualDisplay: VirtualDisplayProviding, @unchecked Sendable {
    public let displayID: CGDirectDisplayID
    private let reference: PadScreenVirtualDisplayRef

    public init(configuration: VirtualDisplayConfiguration = VirtualDisplayConfiguration()) throws {
        try configuration.validate()
        guard PadScreenVirtualDisplayClassesAvailable() else {
            throw VirtualDisplayError.privateAPIUnavailable
        }
        var identifier: CGDirectDisplayID = 0
        guard let reference = PadScreenVirtualDisplayCreate(
            UInt32(configuration.width),
            UInt32(configuration.height),
            configuration.refreshRate,
            &identifier
        ), identifier != 0 else {
            throw VirtualDisplayError.creationFailed
        }
        self.reference = reference
        self.displayID = identifier
    }

    deinit {
        PadScreenVirtualDisplayDestroy(reference)
    }

    public func makePrimaryKeepingPhysicalDisplays() throws {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            throw VirtualDisplayError.settingsRejected
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            throw VirtualDisplayError.settingsRejected
        }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else {
            throw VirtualDisplayError.settingsRejected
        }
        var nextX = Int32(CGDisplayBounds(displayID).width)
        guard CGConfigureDisplayOrigin(configuration, displayID, 0, 0) == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw VirtualDisplayError.settingsRejected
        }
        for display in displays where display != displayID {
            let bounds = CGDisplayBounds(display)
            guard CGConfigureDisplayOrigin(configuration, display, nextX, 0) == .success else {
                CGCancelDisplayConfiguration(configuration)
                throw VirtualDisplayError.settingsRejected
            }
            nextX += Int32(bounds.width)
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
            throw VirtualDisplayError.settingsRejected
        }
    }
}
