@preconcurrency import Network
import Foundation
import PadScreenProtocol

public enum HostServerError: Error, Sendable {
    case invalidPort
}

public struct CodecConfigurationCache: Sendable {
    private var configuration: Data?

    public init() {}

    public mutating func update(_ configuration: Data) {
        self.configuration = configuration
    }

    public func configurationForNewSession() -> Data? { configuration }
}

public final class PadScreenServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 48_596

    private let queue = DispatchQueue(label: "app.padscreen.server", qos: .userInteractive)
    private let inputHandler: @Sendable (PointerMessage) -> Void
    private let stateHandler: @Sendable (String) -> Void
    private var listener: NWListener?
    private var activeClient: HostClientConnection?
    private var codecConfigurationCache = CodecConfigurationCache()

    public init(
        inputHandler: @escaping @Sendable (PointerMessage) -> Void,
        stateHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.inputHandler = inputHandler
        self.stateHandler = stateHandler
    }

    public func start(port: UInt16 = defaultPort) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw HostServerError.invalidPort }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp), on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async {
                self.activeClient?.cancel()
                let client = HostClientConnection(
                    connection: connection,
                    queue: self.queue,
                    inputHandler: self.inputHandler,
                    stateHandler: self.stateHandler,
                    initialCodecConfiguration: self.codecConfigurationCache.configurationForNewSession()
                )
                self.activeClient = client
                client.start()
            }
        }
        listener.stateUpdateHandler = { [stateHandler] state in
            switch state {
            case .ready: stateHandler("listening:\(port)")
            case .failed(let error): stateHandler("listener-error:\(error)")
            default: break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [weak self] in
            self?.activeClient?.cancel()
            self?.activeClient = nil
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    public func send(_ packet: EncodedVideoPacket) {
        queue.async { [weak self] in
            if let configuration = packet.codecConfiguration {
                self?.codecConfigurationCache.update(configuration)
            }
            guard let client = self?.activeClient, client.isStreaming else { return }
            client.sendVideo(packet)
        }
    }
}

private final class HostClientConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let inputHandler: @Sendable (PointerMessage) -> Void
    private let stateHandler: @Sendable (String) -> Void
    private var decoder = FrameDecoder()
    private var processor = HostSessionProcessor()
    private var heartbeat: DispatchSourceTimer?
    private let pendingVideo = OrderedFrameQueue<EncodedVideoPacket>()
    private var videoSendInFlight = false
    private let initialCodecConfiguration: Data?

    var isStreaming: Bool { processor.isStreaming }

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        inputHandler: @escaping @Sendable (PointerMessage) -> Void,
        stateHandler: @escaping @Sendable (String) -> Void,
        initialCodecConfiguration: Data?
    ) {
        self.connection = connection
        self.queue = queue
        self.inputHandler = inputHandler
        self.stateHandler = stateHandler
        self.initialCodecConfiguration = initialCodecConfiguration
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.stateHandler("client-connected")
                self?.receiveNext()
                self?.startHeartbeat()
            case .failed(let error):
                self?.stateHandler("client-error:\(error)")
                self?.cancel()
            case .cancelled:
                self?.stateHandler("client-disconnected")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        heartbeat?.cancel()
        heartbeat = nil
        connection.cancel()
    }

    func send(_ frame: WireFrame) {
        guard let bytes = try? FrameCodec.encode(frame) else { return }
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.stateHandler("send-error:\(error)")
                self?.cancel()
            }
        })
    }

    func sendVideo(_ packet: EncodedVideoPacket) {
        pendingVideo.offer(packet)
        drainVideoIfPossible()
    }

    private func drainVideoIfPossible() {
        guard !videoSendInFlight, let packet = pendingVideo.take() else { return }
        var bytes = Data()
        if let configuration = packet.codecConfiguration,
           let frame = try? FrameCodec.encode(WireFrame(type: .codecConfiguration, payload: configuration)) {
            bytes.append(frame)
        }
        guard let video = try? FrameCodec.encode(WireFrame(type: .video, payload: packet.accessUnit)) else { return }
        bytes.append(video)
        videoSendInFlight = true
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.videoSendInFlight = false
            if let error {
                self.stateHandler("video-send-error:\(error)")
                self.cancel()
            } else {
                self.drainVideoIfPossible()
            }
        })
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            do {
                if let data {
                    for frame in try self.decoder.append(data) {
                        let wasStreaming = self.processor.isStreaming
                        if frame.type == .input {
                            let message = try JSONDecoder.padScreen.decode(PointerMessage.self, from: frame.payload)
                            self.inputHandler(message)
                        }
                        for response in try self.processor.receive(frame) { self.send(response) }
                        if !wasStreaming, self.processor.isStreaming, let configuration = self.initialCodecConfiguration {
                            self.send(WireFrame(type: .codecConfiguration, payload: configuration))
                        }
                        if self.processor.isStreaming { self.stateHandler("streaming") }
                    }
                }
            } catch {
                self.sendProtocolError(error)
                self.cancel()
                return
            }
            if let error {
                self.stateHandler("receive-error:\(error)")
                self.cancel()
            } else if complete {
                self.cancel()
            } else {
                self.receiveNext()
            }
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard self?.isStreaming == true else { return }
            self?.send(WireFrame(type: .heartbeat, payload: Data()))
        }
        heartbeat = timer
        timer.resume()
    }

    private func sendProtocolError(_ error: Error) {
        let payload = Data("{\"message\":\"\(String(describing: error))\"}".utf8)
        send(WireFrame(type: .error, payload: payload))
    }
}
