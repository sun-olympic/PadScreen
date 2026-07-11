import Foundation
import Testing
@testable import PadScreenProtocol

@Test func heartbeatMatchesCrossPlatformGoldenVector() throws {
    let encoded = try FrameCodec.encode(WireFrame(type: .heartbeat, payload: Data()))
    #expect(encoded.map { String(format: "%02x", $0) }.joined() == "504453310106000000000000")
}

@Test func decoderWaitsForCompleteIncrementalFrame() throws {
    let payload = Data("{\"width\":1920}".utf8)
    let bytes = try FrameCodec.encode(WireFrame(type: .hello, payload: payload))
    var decoder = FrameDecoder()

    #expect(try decoder.append(bytes.prefix(5)) == [])
    #expect(try decoder.append(bytes.dropFirst(5).prefix(8)) == [])
    let frames = try decoder.append(bytes.dropFirst(13))

    #expect(frames == [WireFrame(type: .hello, payload: payload)])
}

@Test func decoderEmitsMultipleFramesFromOneRead() throws {
    let first = try FrameCodec.encode(WireFrame(type: .heartbeat, payload: Data()))
    let second = try FrameCodec.encode(WireFrame(type: .error, payload: Data("oops".utf8)))
    var decoder = FrameDecoder()

    #expect(try decoder.append(first + second) == [
        WireFrame(type: .heartbeat, payload: Data()),
        WireFrame(type: .error, payload: Data("oops".utf8)),
    ])
}

@Test func decoderRejectsInvalidMagic() {
    var decoder = FrameDecoder()
    let bytes = Data([0, 0, 0, 0, 1, MessageType.heartbeat.rawValue, 0, 0, 0, 0, 0, 0])

    #expect(throws: ProtocolError.invalidMagic) {
        try decoder.append(bytes)
    }
}

@Test func decoderRejectsUnsupportedVersion() {
    var decoder = FrameDecoder()
    let bytes = Data([0x50, 0x44, 0x53, 0x31, 2, MessageType.heartbeat.rawValue, 0, 0, 0, 0, 0, 0])

    #expect(throws: ProtocolError.unsupportedVersion(2)) {
        try decoder.append(bytes)
    }
}

@Test func decoderRejectsOversizedPayloadBeforeBufferingIt() {
    var decoder = FrameDecoder(maxPayloadSize: 3)
    let bytes = Data([0x50, 0x44, 0x53, 0x31, 1, MessageType.video.rawValue, 0, 0, 0, 0, 0, 4])

    #expect(throws: ProtocolError.payloadTooLarge(4)) {
        try decoder.append(bytes)
    }
}

@Test func helloRoundTripsThroughJSONPayload() throws {
    let hello = HelloMessage(viewportWidth: 2560, viewportHeight: 1600, density: 2, codecs: ["h264"])
    let payload = try JSONEncoder.padScreen.encode(hello)
    #expect(try JSONDecoder.padScreen.decode(HelloMessage.self, from: payload) == hello)
}
