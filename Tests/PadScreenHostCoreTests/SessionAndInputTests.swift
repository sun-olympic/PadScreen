import CoreGraphics
import Foundation
import Testing
import PadScreenProtocol
@testable import PadScreenHostCore

@Test func activatingClientAtomicallyReplacesPreviousClient() {
    var registry = SessionRegistry()
    let first = UUID()
    let second = UUID()

    #expect(registry.activate(first) == nil)
    #expect(registry.activeClient == first)
    #expect(registry.activate(second) == first)
    #expect(registry.activeClient == second)
}

@Test func negotiatorSelectsMvpH264Configuration() throws {
    let hello = HelloMessage(viewportWidth: 2560, viewportHeight: 1600, density: 2, codecs: ["h264"])
    let session = try SessionNegotiator().negotiate(hello)

    #expect(session.width == 1920)
    #expect(session.height == 1200)
    #expect(session.framesPerSecond == 120)
    #expect(session.codec == "h264")
}

@Test func negotiatorRejectsClientWithoutH264() {
    let hello = HelloMessage(viewportWidth: 1920, viewportHeight: 1200, density: 1, codecs: ["av1"])
    #expect(throws: SessionError.noCompatibleCodec) {
        try SessionNegotiator().negotiate(hello)
    }
}

@Test func normalizedCenterMapsToDisplayCenter() throws {
    let mapper = PointerMapper(displayBounds: CGRect(x: 100, y: 50, width: 1920, height: 1200))
    let point = try mapper.map(normalizedX: 0.5, normalizedY: 0.5)

    #expect(point == CGPoint(x: 1060, y: 650))
}

@Test(arguments: [
    (-0.1, 0.5),
    (1.1, 0.5),
    (0.5, -0.1),
    (0.5, 1.1),
    (Double.nan, 0.5),
])
func invalidNormalizedCoordinatesAreRejected(x: Double, y: Double) {
    let mapper = PointerMapper(displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1200))
    #expect(throws: InputError.invalidCoordinates) {
        try mapper.map(normalizedX: x, normalizedY: y)
    }
}

@Test func helloTransitionsProcessorToStreamingAndReturnsSession() throws {
    var processor = HostSessionProcessor()
    let hello = HelloMessage(viewportWidth: 2560, viewportHeight: 1600, density: 2, codecs: ["h264"])
    let frame = WireFrame(type: .hello, payload: try JSONEncoder.padScreen.encode(hello))

    let responses = try processor.receive(frame)

    #expect(processor.isStreaming)
    #expect(responses.map(\.type) == [.session])
    let session = try JSONDecoder.padScreen.decode(SessionMessage.self, from: responses[0].payload)
    #expect(session.width == 1920)
}

@Test func heartbeatDoesNotCreateAnEchoLoop() throws {
    var processor = HostSessionProcessor()
    let hello = HelloMessage(viewportWidth: 1920, viewportHeight: 1200, density: 1, codecs: ["h264"])
    _ = try processor.receive(WireFrame(type: .hello, payload: JSONEncoder.padScreen.encode(hello)))

    #expect(try processor.receive(WireFrame(type: .heartbeat, payload: Data())).isEmpty)
}

@Test func videoBeforeHelloIsRejected() {
    var processor = HostSessionProcessor()
    #expect(throws: HostSessionError.expectedHello) {
        try processor.receive(WireFrame(type: .video, payload: Data()))
    }
}

@Test func videoQueuePreservesReferenceFrameOrder() {
    let queue = OrderedFrameQueue<Int>()
    queue.offer(1)
    queue.offer(2)

    #expect(queue.take() == 1)
    #expect(queue.take() == 2)
    #expect(queue.take() == nil)
}

@Test func invalidVirtualDisplayDimensionsAreRejected() {
    #expect(throws: VirtualDisplayError.invalidConfiguration) {
        try VirtualDisplayConfiguration(width: 0, height: 1200, refreshRate: 60).validate()
    }
}

@Test func defaultVirtualDisplayUses120Hz() {
    #expect(VirtualDisplayConfiguration().refreshRate == 120)
}

@Test func avccAccessUnitConvertsToAnnexB() throws {
    let avcc = Data([0, 0, 0, 2, 0x65, 0xaa, 0, 0, 0, 1, 0x09])
    let annexB = try H264ByteStream.annexB(fromAVCC: avcc)

    #expect(annexB == Data([0, 0, 0, 1, 0x65, 0xaa, 0, 0, 0, 1, 0x09]))
}

@Test func malformedAvccAccessUnitIsRejected() {
    #expect(throws: H264Error.malformedAccessUnit) {
        try H264ByteStream.annexB(fromAVCC: Data([0, 0, 0, 9, 0x65]))
    }
}

@Test func pointerMessageRoundTripsWithoutPixelCoordinates() throws {
    let message = PointerMessage(action: .down, normalizedX: 0.25, normalizedY: 0.75, deltaX: 0, deltaY: 0)
    let data = try JSONEncoder.padScreen.encode(message)

    #expect(try JSONDecoder.padScreen.decode(PointerMessage.self, from: data) == message)
}

@Test func cachedCodecConfigurationIsAvailableToEveryNewSession() {
    var cache = CodecConfigurationCache()
    let configuration = Data([0, 0, 0, 1, 0x67])

    cache.update(configuration)

    #expect(cache.configurationForNewSession() == configuration)
    #expect(cache.configurationForNewSession() == configuration)
}

@Test func defaultEncoderPolicyBoundsFrameDelay() {
    let policy = LowLatencyVideoPolicy.default
    let framesPerSecond = Mirror(reflecting: policy).children
        .first { $0.label == "framesPerSecond" }?.value as? Int

    #expect(policy.maxFrameDelayCount == 1)
    #expect(policy.keyFrameInterval == 120)
    #expect(policy.averageBitRate == 6_000_000)
    #expect(framesPerSecond == 120)
}

@Test func defaultVideoPolicyUsesSmallCaptureBuffer() {
    let policy = LowLatencyVideoPolicy.default
    let queueDepth = Mirror(reflecting: policy).children
        .first { $0.label == "captureQueueDepth" }?.value as? Int

    #expect(queueDepth == 2)
}

@Test func captureQueueHasCapacityBeyondEncoderDelay() {
    let policy = LowLatencyVideoPolicy.default

    #expect(policy.captureQueueDepth > policy.maxFrameDelayCount)
}

@Test func defaultVideoPolicyEnablesHardwareLowLatencyRateControl() {
    let policy = LowLatencyVideoPolicy.default
    let enabled = Mirror(reflecting: policy).children
        .first { $0.label == "enableLowLatencyRateControl" }?.value as? Bool

    #expect(enabled == true)
}

@Test func baselineSPSDeclaresZeroReorderFrames() throws {
    let original = Data([0x27, 0x42, 0x00, 0x32, 0xab, 0x40, 0x3c, 0x01, 0x2f, 0x20])

    let patched = try H264SPSLowLatencyPatcher.patch(original)

    #expect(patched == Data([0x27, 0x42, 0x00, 0x32, 0xab, 0x40, 0x3c, 0x01, 0x2f, 0x40, 0x36, 0x82, 0x21, 0x1a, 0x80]))
}

@Test func encoderProvidedVUIIsPreserved() throws {
    let original = Data([
        0x27, 0x42, 0x00, 0x32, 0x89, 0x8a, 0x1a, 0x03, 0xc0, 0x12,
        0xf4, 0xd4, 0x08, 0x08, 0x08, 0x1e, 0x10, 0x08, 0x46, 0xc0,
    ])

    let patched = try H264SPSLowLatencyPatcher.patch(original)

    #expect(patched == original)
}
