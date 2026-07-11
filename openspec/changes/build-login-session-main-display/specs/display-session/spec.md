## ADDED Requirements

### Requirement: Versioned framed connection
The system SHALL exchange every message in a frame containing the `PDS1` magic, protocol version, message type, reserved bytes, and a bounded big-endian payload length.

#### Scenario: Valid frame arrives incrementally
- **WHEN** a complete supported frame arrives across multiple socket reads
- **THEN** the receiver emits exactly one typed message after all payload bytes arrive

#### Scenario: Invalid or oversized frame arrives
- **WHEN** the receiver encounters invalid magic, an unsupported version, or a payload larger than the configured maximum
- **THEN** it rejects the frame and closes the session with a protocol error

### Requirement: Session negotiation
The Android client MUST send its viewport and decoder capabilities before the host sends video, and the host MUST acknowledge the selected stream configuration.

#### Scenario: Compatible client connects
- **WHEN** the host receives a valid hello containing an H.264 decoder capability
- **THEN** it responds with the selected dimensions, frame rate, codec, and session identifier before sending codec configuration or video frames

#### Scenario: Incompatible client connects
- **WHEN** no mutually supported codec or protocol version exists
- **THEN** the host sends a structured incompatibility error and terminates the connection

### Requirement: Recoverable connection lifecycle
Both applications SHALL expose connection state and automatically recover from transient disconnects while they remain running.

#### Scenario: Connection becomes silent
- **WHEN** no message or heartbeat is received within the session timeout
- **THEN** the endpoint closes the stale session and the Android client retries with bounded exponential backoff

#### Scenario: A second client connects
- **WHEN** a new compatible client completes negotiation while another client is active
- **THEN** the host closes the old session and makes the new client the sole active display session

