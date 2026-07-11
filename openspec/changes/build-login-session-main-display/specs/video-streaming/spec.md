## ADDED Requirements

### Requirement: Low-latency display capture
The macOS host SHALL capture the selected display at a target rate of up to 120 frames per second and MUST bound queued frames so stale frames do not accumulate.

#### Scenario: Encoder is slower than capture
- **WHEN** a newly captured frame arrives while the bounded encoder input is occupied
- **THEN** the host discards stale work rather than growing an unbounded queue

### Requirement: Reference-safe encoded transport
The host and Android client MUST preserve the wire order of encoded H.264 access units and MUST NOT replace an older P-frame with a newer frame.

#### Scenario: Wi-Fi delivers encoded frames in a burst
- **WHEN** multiple H.264 access units become ready while a network send or decoder input buffer is occupied
- **THEN** both endpoints queue and consume those access units in original order so the decoder reference chain remains valid

### Requirement: H.264 stream configuration
The host MUST send H.264 parameter sets before the first decodable access unit and whenever the parameter sets change.

#### Scenario: Client starts a negotiated stream
- **WHEN** session negotiation completes and encoder parameter sets are available
- **THEN** the client receives codec configuration before the first video access unit

### Requirement: Hardware-decoded full-screen rendering
The Android client SHALL configure an available hardware H.264 decoder and render decoded output directly to the active full-screen Surface.

#### Scenario: Surface is recreated
- **WHEN** Android recreates the rendering Surface during rotation or activity lifecycle changes
- **THEN** the client reconfigures decoding and resumes from a subsequent keyframe without requiring the host application to restart

### Requirement: Observable streaming failures
Both endpoints MUST surface capture, encoder, decoder, and transport failures as a user-visible state rather than displaying an unexplained permanent black screen.

#### Scenario: Decoder rejects codec configuration
- **WHEN** MediaCodec cannot accept the received H.264 configuration
- **THEN** the client reports an incompatible-decoder error and reconnects only after the session is reset
