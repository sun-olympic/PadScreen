# PadScreen

PadScreen turns a Xiaomi Pad or another Android tablet into the primary display of a Mac mini **after macOS login**. The MVP uses a trusted local Wi-Fi/LAN connection, H.264 hardware video, and touch-as-pointer input.

## Supported prototype environment

- Apple Silicon Mac running macOS 14 or newer
- Android 12 (API 31) or newer
- Both devices on the same trusted local network
- Xcode 16+ and Android Studio/Android SDK 35 for local builds

## Important startup boundary

PadScreen is user-session software. It cannot display FileVault preboot unlock, Recovery, Safe Mode, firmware UI, or failures that happen before its macOS host starts. First-time setup also requires another way to see the Mac while granting Screen Recording and Accessibility permissions.

Do not disable FileVault automatically. If FileVault remains enabled, unlock the Mac with a physical keyboard before PadScreen can connect. Keep macOS Screen Sharing or SSH enabled as a recovery path when using the tablet as the only post-login screen.

## MVP scope

- 1920x1200 virtual main display at up to 120 Hz
- ScreenCaptureKit capture and VideoToolbox H.264 encoding
- Android MediaCodec rendering to a Surface
- One TCP client, heartbeat, automatic reconnect, and touch input

USB transport, audio, internet relay, clipboard, and pre-login display are intentionally deferred.

## Build

### macOS host

```bash
cd PadScreen
chmod +x scripts/build-macos-app.sh
scripts/build-macos-app.sh
open dist/PadScreen.app
```

The local package is ad-hoc signed for development. Public distribution still requires an Apple Developer ID signature and notarization. For protocol-only testing without virtual-display or screen-capture permission:

```bash
swift run PadScreenHost --synthetic
```

### Android client

```bash
cd PadScreen/android
./gradlew assembleDebug
```

Install `android/app/build/outputs/apk/debug/app-debug.apk` on the tablet, open it, enter the Mac's LAN IP, and tap **连接**. The default TCP port is `48596`.

## First-time setup

1. Keep a physical monitor, macOS Screen Sharing, or another recovery path available.
2. Copy `PadScreen.app` to `/Applications` and open it.
3. From its menu-bar menu, request Screen Recording and Accessibility access. Restart the app after granting Screen Recording if macOS asks.
4. Allow incoming connections if the macOS firewall prompts.
5. Install the Android debug APK and connect both devices to the same trusted network.
6. Enter the Mac's IP address in the tablet app. For Wi-Fi this is often available with `ipconfig getifaddr en0`.
7. Only after restart, sleep/wake, and recovery access have been tested should the tablet be treated as the sole post-login display.

The menu item **切换登录时启动** uses `SMAppService`; run the packaged app from `/Applications`, not the raw SwiftPM executable, for registration.

## Tests

```bash
# Swift protocol, session, input, queue, and H.264 byte-stream tests
swift test

# Zero-download Kotlin protocol and client-core tests
cd android
./gradlew --offline runProtocolTests
```

## CI and releases

GitHub Actions runs the Swift host tests and production app build on an Apple Silicon `macos-14` runner, and runs the Android protocol tests and APK build on Ubuntu for every push to `main` and every pull request.

Pushing a version tag creates a GitHub Release with the macOS app ZIP, Android APK, and SHA-256 checksums:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The automated macOS package is ad-hoc signed but not Developer ID notarized. The Android package is debug signed for direct device testing and is not a Play Store release build.

## Known limitations

- The LAN prototype has no pairing or encryption. Do not expose port `48596` to the internet or an untrusted network.
- The virtual display uses private CoreGraphics classes and can break on a future macOS update.
- FileVault preboot, Recovery, Safe Mode, and early boot are not visible.
- The first tuned stream is fixed at 1920x1200, H.264, up to 120 fps.
- USB, audio, stylus pressure, keyboard forwarding, and automatic host discovery are not included yet.
- The 120 Hz low-latency path is validated on a Xiaomi Pad 6 Pro; other Android decoders may fall back to different buffering behavior.
- Wi-Fi streaming is validated on the same LAN. A 5 GHz access point is recommended because 2.4 GHz jitter can still reduce smoothness even though encoded H.264 frames are now delivered in reference-safe order.
