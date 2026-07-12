import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import VideoToolbox

public enum H264Error: Error, Equatable, Sendable {
    case malformedAccessUnit
    case malformedSPS
    case encoderCreation(OSStatus)
    case encodeFailed(OSStatus)
}

public enum H264SPSLowLatencyPatcher {
    public static func patch(_ nalUnit: Data) throws -> Data {
        guard nalUnit.count > 4, nalUnit[0] & 0x1f == 7 else { throw H264Error.malformedSPS }
        var rbsp: [UInt8] = []
        var zeroCount = 0
        for byte in nalUnit.dropFirst() {
            if zeroCount >= 2, byte == 0x03 {
                continue
            }
            rbsp.append(byte)
            zeroCount = byte == 0 ? min(2, zeroCount + 1) : 0
        }
        var bits: [Bool] = []
        for byte in rbsp {
            for shift in (0..<8).reversed() { bits.append(((byte >> shift) & 1) == 1) }
        }
        var reader = BitReader(bits: bits)
        let profile = try reader.read(8)
        _ = try reader.read(8)
        _ = try reader.read(8)
        _ = try reader.readUE()
        guard [66, 77, 88].contains(profile) else { return nalUnit }

        _ = try reader.readUE()
        let pictureOrderCountType = try reader.readUE()
        if pictureOrderCountType == 0 {
            _ = try reader.readUE()
        } else if pictureOrderCountType == 1 {
            _ = try reader.read(1)
            _ = try reader.readSE()
            _ = try reader.readSE()
            for _ in 0..<(try reader.readUE()) { _ = try reader.readSE() }
        }
        _ = try reader.readUE()
        _ = try reader.read(1)
        _ = try reader.readUE()
        _ = try reader.readUE()
        let frameMbsOnly = try reader.read(1)
        if frameMbsOnly == 0 { _ = try reader.read(1) }
        _ = try reader.read(1)
        if try reader.read(1) == 1 {
            for _ in 0..<4 { _ = try reader.readUE() }
        }
        let vuiFlagIndex = reader.index
        if try reader.read(1) == 1 { return nalUnit }

        var outputBits = Array(bits[..<vuiFlagIndex])
        outputBits.append(true)
        outputBits.append(contentsOf: repeatElement(false, count: 8))
        outputBits.append(true)
        outputBits.append(true)
        appendUE(2, to: &outputBits)
        appendUE(1, to: &outputBits)
        appendUE(16, to: &outputBits)
        appendUE(16, to: &outputBits)
        appendUE(0, to: &outputBits)
        appendUE(1, to: &outputBits)
        outputBits.append(true)
        while outputBits.count % 8 != 0 { outputBits.append(false) }

        let encodedRBSP: [UInt8] = stride(from: 0, to: outputBits.count, by: 8).map { offset in
            outputBits[offset..<(offset + 8)].reduce(UInt8(0)) { ($0 << 1) | ($1 ? 1 : 0) }
        }
        var escaped: [UInt8] = []
        zeroCount = 0
        for byte in encodedRBSP {
            if zeroCount >= 2, byte <= 0x03 {
                escaped.append(0x03)
                zeroCount = 0
            }
            escaped.append(byte)
            zeroCount = byte == 0 ? min(2, zeroCount + 1) : 0
        }
        return Data([nalUnit[0]] + escaped)
    }

    private static func appendUE(_ value: Int, to bits: inout [Bool]) {
        let codeNumber = value + 1
        let width = Int.bitWidth - codeNumber.leadingZeroBitCount
        if width > 1 { bits.append(contentsOf: repeatElement(false, count: width - 1)) }
        for shift in (0..<width).reversed() { bits.append(((codeNumber >> shift) & 1) == 1) }
    }

    private struct BitReader {
        let bits: [Bool]
        var index = 0

        mutating func read(_ count: Int) throws -> Int {
            guard count >= 0, index + count <= bits.count else { throw H264Error.malformedSPS }
            var value = 0
            for bit in bits[index..<(index + count)] { value = (value << 1) | (bit ? 1 : 0) }
            index += count
            return value
        }

        mutating func readUE() throws -> Int {
            var leadingZeros = 0
            while try read(1) == 0 { leadingZeros += 1 }
            return (1 << leadingZeros) - 1 + (leadingZeros == 0 ? 0 : try read(leadingZeros))
        }

        mutating func readSE() throws -> Int {
            let value = try readUE()
            return value.isMultiple(of: 2) ? -(value / 2) : (value + 1) / 2
        }
    }
}

public enum H264ByteStream {
    public static func annexB(fromAVCC data: Data) throws -> Data {
        var offset = 0
        var output = Data()
        while offset < data.count {
            guard offset + 4 <= data.count else { throw H264Error.malformedAccessUnit }
            let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard length > 0, offset + length <= data.count else { throw H264Error.malformedAccessUnit }
            output.append(contentsOf: [0, 0, 0, 1])
            output.append(data[offset..<(offset + length)])
            offset += length
        }
        return output
    }
}

public struct LowLatencyVideoPolicy: Equatable, Sendable {
    public let framesPerSecond: Int
    public let maxFrameDelayCount: Int
    public let keyFrameInterval: Int
    public let averageBitRate: Int
    public let captureQueueDepth: Int
    public let enableLowLatencyRateControl: Bool

    public static let `default` = LowLatencyVideoPolicy(
        framesPerSecond: 90,
        maxFrameDelayCount: 1,
        keyFrameInterval: 23,
        averageBitRate: 6_000_000,
        captureQueueDepth: 2,
        enableLowLatencyRateControl: true
    )
}

public struct EncodedVideoPacket: Sendable {
    public let codecConfiguration: Data?
    public let accessUnit: Data
    public let isKeyFrame: Bool

    public init(codecConfiguration: Data?, accessUnit: Data, isKeyFrame: Bool) {
        self.codecConfiguration = codecConfiguration
        self.accessUnit = accessUnit
        self.isKeyFrame = isKeyFrame
    }
}

public final class H264Encoder: @unchecked Sendable {
    private var session: VTCompressionSession?
    private let output: @Sendable (EncodedVideoPacket) -> Void

    public init(
        width: Int32,
        height: Int32,
        policy: LowLatencyVideoPolicy = .default,
        output: @escaping @Sendable (EncodedVideoPacket) -> Void
    ) throws {
        self.output = output
        var encoderSpecification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
        ]
        if policy.enableLowLatencyRateControl {
            encoderSpecification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        }
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, status, _, sampleBuffer in
                guard status == noErr, let refcon, let sampleBuffer else { return }
                Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue().consume(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw H264Error.encoderCreation(status) }
        session = created
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CAVLC)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: policy.framesPerSecond as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: policy.keyFrameInterval as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: policy.averageBitRate as CFNumber)
        let dataRateLimits = [policy.averageBitRate / 8, 1] as CFArray
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: policy.maxFrameDelayCount as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTCompressionSessionPrepareToEncodeFrames(created)
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    public func encode(_ imageBuffer: CVImageBuffer, presentationTime: CMTime) throws {
        guard let session else { throw H264Error.encoderCreation(-1) }
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        guard status == noErr else { throw H264Error.encodeFailed(status) }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        ) == noErr, let pointer else { return }
        let avcc = Data(bytes: pointer, count: length)
        guard let accessUnit = try? H264ByteStream.annexB(fromAVCC: avcc) else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        let attachment = (attachments as? [[CFString: Any]])?.first
        let isKeyFrame = attachment?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        var configuration: Data?
        if isKeyFrame, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            configuration = Self.codecConfiguration(format)
        }
        output(EncodedVideoPacket(codecConfiguration: configuration, accessUnit: accessUnit, isKeyFrame: isKeyFrame))
    }

    private static func codecConfiguration(_ format: CMFormatDescription) -> Data? {
        var output = Data()
        for index in 0..<2 {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            var count = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil
            )
            guard status == noErr, let pointer else { return nil }
            let parameterSet = Data(bytes: pointer, count: size)
            let emitted = index == 0 ? ((try? H264SPSLowLatencyPatcher.patch(parameterSet)) ?? parameterSet) : parameterSet
            output.append(contentsOf: [0, 0, 0, 1])
            output.append(emitted)
        }
        return output
    }
}

public final class ScreenCaptureEncoder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let displayID: CGDirectDisplayID
    private let encoder: H264Encoder
    private let policy: LowLatencyVideoPolicy
    private let sampleQueue = DispatchQueue(label: "app.padscreen.capture", qos: .userInteractive)
    private var stream: SCStream?
    private var idleFrameTimer: DispatchSourceTimer?
    private var latestImageBuffer: CVImageBuffer?
    private var lastCaptureUptimeNanoseconds: UInt64 = 0
    private var lastEncodePresentationTime = CMTime.invalid

    public init(displayID: CGDirectDisplayID, width: Int = 1920, height: Int = 1200,
                policy: LowLatencyVideoPolicy = .default,
                output: @escaping @Sendable (EncodedVideoPacket) -> Void) throws {
        self.displayID = displayID
        self.policy = policy
        self.encoder = try H264Encoder(width: Int32(width), height: Int32(height), policy: policy, output: output)
    }

    public func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw VirtualDisplayError.creationFailed
        }
        let configuration = SCStreamConfiguration()
        configuration.width = 1920
        configuration.height = 1200
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(policy.framesPerSecond))
        configuration.queueDepth = policy.captureQueueDepth
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        try await stream.startCapture()
        sampleQueue.async { [weak self] in self?.startIdleFrameTimer() }
    }

    public func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        sampleQueue.async { [weak self] in
            self?.idleFrameTimer?.cancel()
            self?.idleFrameTimer = nil
            self?.latestImageBuffer = nil
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestImageBuffer = imageBuffer
        lastCaptureUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        encodeWithMonotonicTimestamp(imageBuffer)
    }

    private func startIdleFrameTimer() {
        guard idleFrameTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / 60)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let imageBuffer = self.latestImageBuffer else { return }
            let idleNanoseconds = DispatchTime.now().uptimeNanoseconds &- self.lastCaptureUptimeNanoseconds
            guard idleNanoseconds >= 12_000_000 else { return }
            self.encodeWithMonotonicTimestamp(imageBuffer)
        }
        idleFrameTimer = timer
        timer.resume()
    }

    private func encodeWithMonotonicTimestamp(_ imageBuffer: CVImageBuffer) {
        let clockTime = CMClockGetTime(CMClockGetHostTimeClock())
        let minimumStep = CMTime(value: 1, timescale: 1_000_000)
        let minimumTime = lastEncodePresentationTime.isValid
            ? CMTimeAdd(lastEncodePresentationTime, minimumStep)
            : clockTime
        let presentationTime = CMTimeCompare(clockTime, minimumTime) >= 0 ? clockTime : minimumTime
        lastEncodePresentationTime = presentationTime
        try? encoder.encode(imageBuffer, presentationTime: presentationTime)
    }
}
