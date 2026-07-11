## ADDED Requirements

### Requirement: Resolution-independent pointer input
The Android client SHALL encode touch position as normalized coordinates and the macOS host SHALL map them into the active virtual-display bounds.

#### Scenario: User taps the center of the tablet
- **WHEN** Android sends a primary tap at normalized coordinates `(0.5, 0.5)`
- **THEN** macOS emits pointer movement and a click at the center of the virtual display

### Requirement: Drag and scroll gestures
The system SHALL preserve ordered pointer down, move, up, cancel, and scroll actions for the active session.

#### Scenario: User drags an item
- **WHEN** the client sends down followed by ordered move events and up for one pointer identifier
- **THEN** the host emits a continuous primary-button drag ending with button release

### Requirement: Permission-aware input injection
The host MUST NOT report remote input as ready until macOS Accessibility authorization permits event injection.

#### Scenario: Accessibility access is denied
- **WHEN** a valid input message arrives without Accessibility authorization
- **THEN** the host ignores the event, reports input permission required, and leaves video streaming active

### Requirement: Input validation
The host MUST reject non-finite or out-of-range normalized coordinates and unknown input actions.

#### Scenario: Malformed pointer event arrives
- **WHEN** an input message contains invalid coordinates or an unsupported action
- **THEN** the host does not inject an event and reports a protocol validation error
