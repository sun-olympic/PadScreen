## Why

Mac mini users need a way to reuse an Android tablet as the computer's primary display after macOS login, without buying a dedicated monitor. The first release should prove that a headless Mac can establish a dependable, low-latency display session over a local network while clearly preserving the startup and FileVault limitations of a software-only solution.

## What Changes

- Add a native macOS host that creates a tablet-sized virtual display, captures it, encodes frames with hardware acceleration, and streams them over the local network.
- Add an Android tablet client that discovers or directly connects to the host, decodes the stream, renders it full-screen, and reports connection state.
- Add a framed, versioned wire protocol for session negotiation, video configuration, encoded frames, heartbeats, errors, and input events.
- Add touch-to-pointer input forwarding with explicit macOS Accessibility permission handling.
- Add automatic reconnect and host-side session replacement so the tablet can recover after sleep, Wi-Fi interruption, or host restart after login.
- Document that first-time setup needs another way to view the Mac and that FileVault preboot, Recovery, Safe Mode, and early startup are outside the software-only display boundary.

## Capabilities

### New Capabilities

- `display-session`: Pairing-free local MVP connection lifecycle, protocol negotiation, heartbeat, disconnect, and reconnect behavior.
- `video-streaming`: macOS display capture and H.264 encoding plus Android hardware decoding and full-screen rendering.
- `virtual-main-display`: Creation and lifecycle of a headless virtual display sized for the Android tablet and selected as the post-login primary display.
- `remote-input`: Android touch gesture encoding and macOS pointer-event injection with permission-aware failure handling.

### Modified Capabilities

None.

## Impact

- New Swift Package and macOS application targets using AppKit, ScreenCaptureKit, VideoToolbox, Network, and CoreGraphics.
- New Android Gradle project using Kotlin, Jetpack Compose, MediaCodec, and TCP sockets.
- The macOS virtual-display implementation relies on private CoreGraphics symbols, so distribution is expected to be signed and notarized outside the Mac App Store.
- Screen Recording and Accessibility permissions are required on macOS. Local-network access is required on both devices.
