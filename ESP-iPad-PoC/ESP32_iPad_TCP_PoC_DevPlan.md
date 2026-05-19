# ESP32-S3 ↔ iPad TCP Control Link — Proof-of-Concept Dev Plan

## 1. Architecture Overview

- **ESP32-S3-N16R8** acts as a TCP server with a static IP on the local WLAN.
- **iPad (iPadOS 26.x)** acts as a TCP client, connecting to the ESP32's known IP and port.
- **Transport:** Single persistent TCP socket (full-duplex). No second port.
- **Payload:** Single ASCII character per frame (`'0'`–`'F'`).
- **Rate:** Event-driven transmissions. If no data changes for 1 second, both sides send a heartbeat.
- **Fail-safe:** ESP32 auto-locks (placeholder action) after 300 seconds of no valid iPad command.

## 2. Network Configuration

| Parameter | Value (Placeholder) |
|-----------|---------------------|
| SSID | `MyLabNetwork` |
| Password | `LabPassword123` |
| ESP32 Static IP | `192.168.1.100` |
| ESP32 Gateway | `192.168.1.1` |
| ESP32 Subnet | `255.255.255.0` |
| TCP Listen Port | `8080` |
| iPad IP | Assigned via DHCP (typically `192.168.1.x`) |

> **Note:** The ESP32 must use a static IP. Do not rely on DHCP for the server endpoint.

## 3. Protocol Specification

### 3.1 Framing
- Each logical message is **exactly one byte**: an ASCII character `'0'`–`'F'`.
- TCP is a byte stream; the receiver must read bytes and treat each byte as an independent command.
- No JSON, no length prefix, no delimiters.

### 3.2 iPad → ESP32 Commands

| Code | Name | Action |
|------|------|--------|
| `'0'` | **Heartbeat** | No action. Resets the 300-second comms-loss timer. |
| `'1'` | **LED Test** | Turn the on-board RGB LED (GPIO48) solid red. |
| `'2'` | **Lock** | *Reserved / Placeholder.* Labeled but performs no action in this PoC. |
| `'3'` | **Unlock** | *Reserved / Placeholder.* Labeled but performs no action in this PoC. |
| `'4'`–`'F'` | **Reserved** | No action. |
| `'5'` | *Reserved / BOOT* | No action (reserved; ESP32 uses `'5'` for BOOT button TX). |

### 3.3 ESP32 → iPad Status Reports

| Code | Name | Meaning |
|------|------|---------|
| `'0'` | **Heartbeat** | No action. Indicates the ESP32 is alive. |
| `'1'` | **LED Test Ack** | Confirms the LED test command was received and executed. |
| `'2'` | **State: Locked** | Reports the placeholder lock state is *engaged*. |
| `'3'` | **State: Unlocked** | Reports the placeholder lock state is *disengaged*. |
| `'4'` | **State: Fault** | Reports a placeholder fault condition. |
| `'5'` | **BOOT Signal** | Sent when the on-board BOOT button (GPIO0) is pressed. |
| `'6'`–`'F'` | **Reserved** | Ignored by the iPad app. |

### 3.4 Timing Rules
1. **Event-driven:** Either side sends immediately when its local state changes.
2. **Heartbeat:** If no transmission has occurred in the last **1 second**, send `'0'` automatically.
3. **ESP32 Fail-safe:** If no valid byte is received from the iPad for **300 seconds**, the ESP32 transitions its internal lock state to *locked* (placeholder). This timeout must be a `#define` or `const` at the top of the firmware for easy editing.

## 4. ESP32 Firmware Plan

### 4.1 Hardware Targets
- **Board:** ESP32-S3-N16R8 (Arduino IDE board target: `ESP32S3 Dev Module`).
- **Board:** ESP32-S3-N16R8 (Arduino IDE board target: `ESP32S3 Dev Module`).
- **RGB LED:** GPIO48 (WS2812). The RGB solder pads are already bridged per hardware manual.
- **BOOT Button:** GPIO0 (active LOW, internal pull-up).
- **Network:** Wi-Fi STA mode with static IP.
- **Server:** TCP listener on port `8080`. |

### 4.2 Core Loop Logic
```
SETUP:
  - Configure Wi-Fi with static IP, connect to SSID.
  - Initialize GPIO48 RGB LED (off state).
  - Start TCP server on port 8080.
  - Initialize comms-loss timer to 300s.

LOOP:
  - Accept or maintain one TCP client connection.
  - If client connected:
      - Read available bytes from TCP stream (one byte = one command).
      - For each byte received:
          - Reset comms-loss timer to 300s.
          - If byte == '0': do nothing (heartbeat).
          - If byte == '1': set RGB LED to red; send '1' back to iPad; schedule auto-off in 1s.
          - If byte == '2': label as LOCK; do nothing.
          - If byte == '3': label as UNLOCK; do nothing.
          - If byte >= '4' and <= 'F': do nothing.
      - If BOOT button (GPIO0) pressed: debounce and send '5' to iPad.
      - If LED test active and 1s elapsed: turn RGB LED off.
      - If no transmission in last 1s, send '0' (heartbeat) to iPad.
  - If client not connected:
      - Listen for new client.
      - Continue decrementing comms-loss timer.
  - If comms-loss timer reaches 0:
      - Set internal lock state to LOCKED (placeholder).
      - (Optional) Send '2' to iPad if a client is connected.
      - Hold at 0 until a new command arrives.
```

### 4.3 Key Implementation Notes
- Use `WiFiServer` / `WiFiClient` from the ESP32 Arduino core.
- RGB LED requires the **Adafruit NeoPixel** (or equivalent) library; initialize with `NUM_RGB_LEDS = 1`.
- The 300-second timeout must be declared as a configurable constant at the top of the sketch.
- **Do not use `delay()` in the main loop.** All timed events (heartbeat, LED auto-off, fail-safe) must use `millis()`-based non-blocking scheduling so the TCP socket is never starved. |

## 5. iPad Swift App Plan

### 5.1 App Structure
- **Main View:** A single screen with two indicators:
  - **Red indicator:** Lights up when the ESP32 reports `'1'` (LED Test Ack).
  - **Blue indicator:** Lights up when the ESP32 reports `'5'` (BOOT button press). Both indicators auto-reset to default after **1 second**.
- **Debug View:** A dedicated developer/diagnostic screen accessible from the main UI (e.g., via a navigation button or hidden gesture).

### 5.2 TCP Client Behavior
- On app launch / scene activation: attempt to connect to `192.168.1.100:8080`.
- Maintain the connection while the app is foregrounded.
- If the connection drops, enter a reconnection loop with exponential backoff (max ~5s).
- Send `'0'` automatically every 1 second if no other command has been sent.

### 5.3 Debug Screen Requirements

The debug screen must expose the following diagnostics. Use standard iOS APIs (`Network.framework` or `CocoaAsyncSocket` if needed; `URLSession` is not suitable for persistent raw TCP).

| Diagnostic | Implementation Requirement |
|------------|---------------------------|
| **Connection State Machine** | Display current state: `Disconnected`, `Resolving`, `Connecting`, `Connected`, `Reconnecting (N s)`. |
| **RX / TX Payload** | Show the last character received and the last character sent, with a timestamp (`HH:mm:ss.SSS`). |
| **Frame Counter & FPS** | Count valid frames received per second. Display a running average or bar over the last 5 seconds. |
| **Error Log (last 20)** | Append-only list of errors: TCP errors, parse errors, timeout events, connection drops. |
| **Force Reconnect** | A button that closes the current socket and immediately initiates a new connection attempt. |
| **Raw Packet Hex Dump** | Display the last 10 bytes received in hex format (e.g., `0x31`, `0x30`). |
| **Network Vitals** | Show: local IP address, target IP (`192.168.1.100`), target port (`8080`). |
| **Manual Command Injector** | A grid of 16 buttons (`0`–`F`). Tapping a button sends that character to the ESP32 immediately. |

### 5.4 UI State Mapping
- When the app receives `'1'` from the ESP32: set the main screen red indicator to ON.
- When the app receives `'5'` from the ESP32: set the main screen blue indicator to ON; auto-reset after 1 s.
- When the app receives `'2'`, `'3'`, or `'4'`: log them in the debug view; no main UI change required for this PoC.
- When the user taps a manual injector button or a main UI action button: send the corresponding ASCII code and log it in the TX panel.

## 6. Command Reference (Quick Lookup)

### iPad → ESP32
| Char | Hex | Purpose |
|------|-----|---------|
| `0` | `0x30` | Heartbeat |
| `1` | `0x31` | LED Test (Red) |
| `2` | `0x32` | Lock (placeholder) |
| `3` | `0x33` | Unlock (placeholder) |
| `4` | `0x34` | Reserved |
| `5` | `0x35` | BOOT Button Signal (ESP32 → iPad) |
| `6`–`F` | `0x36`–`0x46` | Reserved |

### ESP32 → iPad
| Char | Hex | Purpose |
|------|-----|---------|
| `0` | `0x30` | Heartbeat |
| `1` | `0x31` | LED Test Ack |
| `2` | `0x32` | State: Locked |
| `3` | `0x33` | State: Unlocked |
| `4` | `0x34` | State: Fault |
| `5` | `0x35` | BOOT Button Signal |
| `6`–`F` | `0x36`–`0x46` | Reserved |

## 7. Development Milestones

1. **M1 — ESP32 Standalone:** Static IP, TCP server running, accepts any byte and prints it to Serial. RGB LED turns on/off via Serial commands for hardware verification.
2. **M2 — Protocol Loop:** Implement full command parser, heartbeat generator, and 300-second fail-safe timer. Verify with a desktop TCP client (e.g., `nc`, Packet Sender).
3. **M3 — iPad TCP Client:** Swift app connects, sends `'1'`, receives `'1'`, updates a basic label color.
4. **M4 — Debug Screen:** Implement all 8 diagnostic panels and the manual command injector.
5. **M5 — Integration & Stress Test:** Rapid command injection, Wi-Fi dropout/reconnect, verify 300s fail-safe, verify 1 Hz heartbeat cadence, verify BOOT button sends `'5'`, verify LED auto-off after 1 s.

## 8. Notes & Constraints

- **No mDNS:** IP addresses are hardcoded for this internal PoC. Both devices are assumed to be on the same private subnet.
- **No Security:** No TLS, no authentication, no MAC filtering. This is a closed-lab proof-of-concept.
- **No Background Operation:** The iPad app is expected to remain foregrounded. If backgrounded, the TCP connection may be suspended by iPadOS; reconnect on foregrounding.
- **Solenoid Out of Scope:** Commands `2`, `3`, and `4` are reserved and labeled for future use but perform no hardware action in this PoC.
- **TCP Stream Parsing:** Because TCP is a stream, the iPad must read bytes into a buffer and process each byte individually. Do not assume one `read()` equals one command.
