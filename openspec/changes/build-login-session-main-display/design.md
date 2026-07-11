## Context

PadScreen is a new two-application system: a macOS host running inside a logged-in user session and an Android client running on a Xiaomi Pad. The host must keep a virtual display alive, capture and encode it, accept one tablet connection, and inject returned pointer events. The client must establish a local TCP session, configure a hardware decoder, render with minimal buffering, and reconnect without user intervention.

The software-only boundary begins after macOS has unlocked the startup disk and created a user session. First-time privacy authorization, FileVault preboot, Recovery, Safe Mode, and failures before the host launches require another display or recovery channel.

## Goals / Non-Goals

**Goals:**

- Demonstrate a usable post-login primary-display session at 1920x1200, up to 120 fps, over a trusted local network or USB-forwarded TCP connection.
- Keep protocol parsing, session state, coordinate mapping, and reconnection behavior independently testable.
- Use hardware H.264 encode/decode and bound buffering to favor latency over perfect frame delivery.
- Build native, dependency-light applications that can be compiled locally with Xcode and Android Studio.
- Surface permission and compatibility failures instead of silently presenting a black screen.

**Non-Goals:**

- Rendering FileVault preboot, Recovery, Safe Mode, firmware, or early macOS startup screens.
- USB transport, audio, stylus pressure, clipboard, file transfer, multi-client sessions, or internet relay in the MVP.
- App Store distribution or support for every macOS/Android release.
- Encryption against a hostile LAN in the initial prototype; deployment beyond a trusted LAN requires an authenticated encrypted transport.

## Decisions

### Native host and client

The macOS host will use Swift/AppKit and the Android client will use Kotlin/Compose. This provides direct access to ScreenCaptureKit, VideoToolbox, Network.framework, MediaCodec, and Surface without cross-platform runtime overhead. A shared implementation language was considered, but the latency-critical platform APIs would still need substantial native bridges.

### One ordered TCP connection for the MVP

Control messages, H.264 access units, heartbeats, and input events will share one TCP connection. Each message has a fixed 12-byte header: four-byte `PDS1` magic, one-byte protocol version, one-byte message type, two reserved bytes, and a four-byte big-endian payload length. Control payloads are UTF-8 JSON; video payloads are raw length-prefixed H.264 access units.

TCP was selected because it minimizes implementation and pairing complexity and makes the first cross-platform protocol deterministic. Head-of-line blocking is accepted for the MVP. Raw capture work may be coalesced before encoding, but encoded H.264 access units are sent and decoded through ordered FIFO queues because arbitrary P-frame loss corrupts the reference chain. QUIC/UDP remains an upgrade path after measured evidence shows TCP is the bottleneck.

### Explicit session negotiation

The Android client opens with a `hello` message containing protocol version, viewport size, density, and decoder capabilities. The host responds with `session` metadata and an H.264 configuration message before video frames. Unknown versions, oversized frames, and invalid state transitions close the connection with a structured error.

### Private virtual-display adapter isolated behind a protocol

The host defines a `VirtualDisplayProviding` boundary. The production adapter declares the private CoreGraphics virtual-display Objective-C classes in one compatibility module and creates a 1920x1200@120 display. The rest of the host sees only a display ID and lifecycle methods. This isolates macOS-version fragility and permits tests to use a fake provider.

If virtual-display creation fails, the host may capture an existing display for development, but it MUST report that the headless-primary-display requirement is unavailable rather than silently claiming success.

### ScreenCaptureKit plus VideoToolbox

ScreenCaptureKit supplies BGRA frames for the virtual display. VideoToolbox encodes baseline-compatible H.264 in real time with frame reordering disabled, low-latency rate control, an expected frame rate of 120, a bounded capture queue, and periodic keyframes. The host sends codec parameter sets before the first keyframe and whenever they change.

### MediaCodec renders directly to a Surface

The Android client configures `MediaCodec` from the received SPS/PPS and renders output directly to a full-screen 120 Hz Surface. It does not convert frames through Bitmap objects. MediaCodec input and output use asynchronous callbacks, and encoded access units enter the decoder in wire order so P-frame dependencies are preserved across short Wi-Fi bursts.

### Normalized remote pointer events

Android sends pointer coordinates normalized to `[0,1]`, an action, pointer identifier, button state, and optional scroll deltas. The Mac maps coordinates into the virtual display bounds and emits CoreGraphics events. This avoids coupling the protocol to device pixels or display scaling. Input remains disabled until Accessibility authorization is present.

### Process model and recovery

The MVP is a user-session menu-bar app with an optional login-item registration. It owns the virtual display, listener, capture stream, encoder, and one active client. A newer client atomically replaces an older session. Both sides use heartbeats and exponential reconnect capped at five seconds. A later production hardening phase may split a watchdog/helper from the user agent, but a root daemon cannot itself access WindowServer and is not used for capture.

## Risks / Trade-offs

- [Private virtual-display APIs can change] → Keep declarations isolated, fail with a compatibility error, test supported macOS releases, and retain existing-display capture as a developer diagnostic mode.
- [Mac App Store rejection] → Sign and notarize for direct distribution; do not design around sandbox-only assumptions.
- [TCP stalls increase latency] → Bound or coalesce raw capture work before encoding, preserve encoded reference-frame order, collect latency metrics, and retain a protocol path for QUIC or keyframe-aware recovery if prolonged stalls require bounded transport queues.
- [Screen Recording or Accessibility permission missing] → Publish explicit readiness state and deep-link to the corresponding System Settings pane.
- [Network loss leaves the user without a screen] → Auto-reconnect, keep Screen Sharing/SSH as documented recovery options, and never disable physical displays.
- [FileVault prevents a visible cold boot] → State this during onboarding and support either post-unlock manual keyboard entry or FileVault-off automatic login; do not weaken security automatically.
- [Private API sample code licensing] → Implement declarations and behavior from platform observation/documentation; do not copy GPL implementation code into this project.

## Migration Plan

This is a greenfield application with no data migration. Development rollout is incremental: validate protocol vectors, validate host/client sockets with synthetic H.264 data, validate existing-display capture, validate private virtual-display creation, then test a fully headless Mac mini. Rollback consists of quitting/uninstalling the login item; the virtual display disappears when its owner process exits.

## Open Questions

- Which Xiaomi Pad model and native aspect ratio should become the first tuned resolution profile?
- Does the target network require authenticated encryption in the first distributable build rather than after the LAN prototype?
- Which macOS releases continue to accept the selected private virtual-display declarations without changes?
