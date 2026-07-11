## ADDED Requirements

### Requirement: Tablet-sized virtual display
The macOS host SHALL create one virtual display matching the negotiated tablet aspect ratio, using 1920x1200 at 120 Hz as the low-latency default.

#### Scenario: Host starts without a physical monitor
- **WHEN** the user-session host starts on a supported macOS release
- **THEN** it creates an online virtual display and publishes its display identifier to the capture subsystem

### Requirement: Post-login primary display
The host SHALL arrange the virtual display as the post-login primary display without disabling any connected physical display.

#### Scenario: Virtual display becomes ready
- **WHEN** virtual-display creation succeeds
- **THEN** the host positions it at the desktop origin and keeps any physical display available for recovery

### Requirement: Compatibility failure is explicit
The host MUST distinguish failure to create a virtual display from failure to stream an otherwise existing display.

#### Scenario: Private API is unavailable
- **WHEN** required virtual-display classes or selectors are unavailable on the running macOS release
- **THEN** the host enters an unsupported-virtual-display state and does not claim headless-primary-display readiness

### Requirement: Startup boundary disclosure
The product MUST state that the virtual display is unavailable before the user-session host runs.

#### Scenario: User enables launch at login
- **WHEN** the user configures PadScreen as the only post-login display
- **THEN** onboarding explains that FileVault preboot, Recovery, Safe Mode, and first-time permissions still require a separate recovery method
