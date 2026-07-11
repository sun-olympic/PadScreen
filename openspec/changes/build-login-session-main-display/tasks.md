## 1. Project Setup

- [x] 1.1 Create the Swift package, macOS app source layout, and macOS test target
- [x] 1.2 Create the Android Gradle application, Compose activity, and Android unit-test layout
- [x] 1.3 Add project documentation for supported systems, privacy permissions, and startup limitations

## 2. Cross-Platform Protocol

- [x] 2.1 Add failing Swift tests for frame encoding, incremental decoding, validation, and golden protocol vectors
- [x] 2.2 Implement the Swift frame codec and message models to pass the protocol tests
- [x] 2.3 Add failing Kotlin tests using the same golden vectors, then implement the Kotlin frame codec and models

## 3. macOS Host

- [x] 3.1 Add failing tests for session state transitions, client replacement, and normalized pointer mapping
- [x] 3.2 Implement the TCP session server, negotiation, heartbeat, and reference-order-preserving outbound video queue
- [x] 3.3 Implement the isolated CoreGraphics virtual-display adapter and explicit compatibility errors
- [x] 3.4 Implement ScreenCaptureKit capture and low-latency VideoToolbox H.264 encoding
- [x] 3.5 Implement permission-aware CoreGraphics pointer injection
- [x] 3.6 Implement the menu-bar status app and login-item control

## 4. Android Client

- [x] 4.1 Add failing tests for reconnect backoff, client connection state, and touch normalization
- [x] 4.2 Implement the TCP client, negotiation, heartbeat, frame parsing, and automatic reconnect
- [x] 4.3 Implement the MediaCodec H.264 decoder with Surface lifecycle recovery
- [x] 4.4 Implement the full-screen Compose UI, connection status, host configuration, and touch forwarding

## 5. Integration and Resilience

- [x] 5.1 Add a synthetic host mode and verify protocol negotiation without screen-capture permission
- [x] 5.2 Bound pre-encode capture work, preserve encoded H.264 order through transport and decoding, and verify Wi-Fi burst behavior
- [x] 5.3 Verify reconnect behavior after socket loss and Android Surface recreation

## 6. Verification and Handoff

- [x] 6.1 Run Swift and Android unit tests and resolve all failures
- [x] 6.2 Build the macOS executable and Android debug APK
- [x] 6.3 Document local build, first-time setup, run commands, known limitations, and headless Mac mini validation steps
