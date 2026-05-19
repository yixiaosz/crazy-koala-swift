# Crazy Koala — iPad Native Development Plan

> **Purpose:** High-level guidance for migrating the Windows/Kivy codebase to a native iPad (Swift/SwiftUI) project. This document is intended for AI agents and developers who will implement the new codebase. Refer to the original implementation using paths prefixed with `/windows-version/...`.
>
> **Design principle:** Functionality over visual fidelity. Keep all UI simple, straightforward, and minimal. No decorative flourishes. Use the system keyboard and standard iOS patterns. Custom font **Poppins** is required.

---

## 1. Project Overview

The app is a kiosk-style touchscreen interface for a physical community-sharing box ("Crazy Koala"). Users deposit items, retrieve items, or browse completed "happy memory" cycles. The original Windows version uses Python + Kivy + OpenCV + SQLite. This plan describes the native iPad rewrite.

**Original entry point and screen manager:** `/windows-version/main.py`

---

## 2. Adopted Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **UI Framework** | SwiftUI | Declarative, fast to iterate, native iPad support |
| **Camera** | `AVCaptureSession` + `AVCaptureVideoPreviewLayer` (UIKit bridge) | Native hardware pipeline, no OpenCV |
| **Audio Recording** | `AVAudioRecorder` (M4A/AAC) | Native, replaces `sounddevice` + `wave`; ~10× smaller than WAV |
| **Audio Playback** | `AVAudioPlayer` | Native, replaces `playsound` |
| **Database** | GRDB (Swift wrapper over SQLite) | Preserves existing SQL schema and queries |
| **File System** | `FileManager` | Sandboxed app container |
| **Network** | `Network.framework` (`NWConnection`) | Persistent TCP client to ESP32-S3 |
| **Fonts** | Poppins family (TTF) registered in `Info.plist` | Required brand font |

---

## 3. Directory Structure

```
crazy-koala-swift/
├── AGENTS.md                        # Development protocol for AI agents
├── project-dev-plan.md              # Project Development Plan
├── windows-version/                 # Original Python app for reference
├── App/
│   └── CrazyKoalaApp.swift          # @main entry point
├── Models/
│   ├── Item.swift                   # GRDB-compatible model matching existing schema
│   └── ItemStore.swift              # CRUD + file validation (replaces db_operations.py)
├── Services/
│   ├── DatabaseService.swift        # GRDB queue setup + connection (replaces db_setup.py)
│   ├── CameraService.swift          # AVCaptureSession wrapper + photo capture
│   ├── AudioService.swift           # AVAudioRecorder + AVAudioPlayer wrapper
│   └── TCPClientService.swift       # NWConnection + ESP32 protocol (§5.4)
├── Views/
│   ├── HomeView.swift               # Landing screen + mode selection
│   ├── DepositFlow/
│   │   ├── InputNameView.swift      # Text input for item name
│   │   ├── PhotoAudioView.swift     # Camera preview + audio recording
│   │   └── OpenDoorView.swift       # Door-open instruction screen
│   ├── TakeFlow/
│   │   ├── SelectItemView.swift     # Grid of unretrieved items
│   │   └── ViewDepositView.swift    # Deposit detail before retrieval
│   └── Memories/
│       ├── GalleryView.swift        # Grid of completed memories
│       └── DetailView.swift         # Side-by-side deposit/take detail
│   ├── DebugView.swift              # ESP32 diagnostics sheet (§6.9)
├── Components/
│   ├── YellowBar.swift              # Simple yellow header bar
│   └── RoundedButton.swift          # Simple button with corner radius
└── Assets/
    ├── fonts/
    │   └── Poppins/                 # TTF files from /assets/fonts/
    ├── images/                      # PNG assets from /assets/
    └── sounds/                      # Audio assets (all M4A/AAC)

```

---

## 4. Data Model

### 4.1 Database Schema (Preserve Exactly)

The existing SQLite schema from `/windows-version/database/db_setup.py` must be preserved:

```sql
CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    deposit_photo_path TEXT,
    deposit_audio_path TEXT,
    deposit_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    taken_photo_path TEXT,
    taken_audio_path TEXT,
    taken_created_at TIMESTAMP
);
```

**GRDB mapping:** Create a Swift `struct Item: Codable, FetchableRecord, PersistableRecord` with properties matching these columns exactly. Use `Date` for timestamp columns.

### 4.2 CRUD Operations (Port from `/windows-version/database/db_operations.py`)

Implement the following operations in `ItemStore.swift`:

1. **`insertDeposit(name: String, depositPhotoPath: String?, depositAudioPath: String?)`**
   - Insert a new row with deposit paths.

2. **`updateTaken(itemName: String, takenPhotoPath: String?, takenAudioPath: String?)`**
   - Update the row matching `name`, setting `taken_photo_path`, `taken_audio_path`, and `taken_created_at = CURRENT_TIMESTAMP`.

3. **`fetchAllItems() -> [Item]`**
   - Query rows where both `deposit_photo_path` and `taken_photo_path` are not NULL.
   - **Critical:** Validate that both photo files actually exist on disk using `FileManager`. Skip and log any rows with missing files. This behavior is identical to the current Python implementation.

4. **`fetchUnretrievedItems() -> [(name: String, photoPath: String)]`**
   - Query rows where `taken_created_at IS NULL`.
   - Validate that `deposit_photo_path` exists on disk. Return only valid items.

5. **`fetchItemDetails(name: String) -> Item?`**
   - Fetch a single row by name. Return nil if not found.

### 4.3 File Storage Convention

Maintain the same on-disk layout as the original:

```
Documents/
├── items.db
└── data/
    └── {item_name}/
        ├── {item_name}_deposit_photo.jpg
        ├── {item_name}_deposit_audio.m4a
        ├── {item_name}_taken_photo.jpg
        └── {item_name}_taken_audio.m4a
```

**Validation rule:** Never trust paths stored in the database alone. Always verify with `FileManager.default.fileExists(atPath:)` before displaying or returning an item. This matches the current `os.path.exists` validation in `/windows-version/database/db_operations.py`.

---

## 5. Services

### 5.1 DatabaseService

**Responsibility:** Initialize GRDB, create the `items` table if missing, and expose a shared `DatabaseQueue`.

**Reference:** `/windows-version/database/db_setup.py`

**Requirements:**
- Open `items.db` from the app's `Documents` directory.
- On first launch, create the table using the exact SQL schema above.
- Use a `DatabaseQueue` for thread-safe access.

### 5.2 CameraService

**Responsibility:** Manage `AVCaptureSession`, display live preview, and capture still photos.

**Reference:** Camera logic in `/windows-version/screens/deposit/photo_audio_record.py`

**Requirements:**
- Configure an `AVCaptureSession` with `.photo` preset.
- Use the **front-facing camera** by default (the original code rotates images 180°, implying the camera is mounted upside-down; front camera is the closest semantic match for a self-facing kiosk).
- Provide a live preview via `AVCaptureVideoPreviewLayer`.
- Capture a full-resolution `AVCapturePhoto` when triggered.
- Save the resulting image to a temporary location as JPEG.
- **Do not** implement manual rotation, BGR→RGB conversion, or texture blitting — `AVCaptureSession` handles this natively.
- Provide a method to start/stop the session to conserve battery.

### 5.3 AudioService

**Responsibility:** Record audio to **M4A (AAC)** and play back audio files.

**Reference:** Audio logic in `/windows-version/screens/deposit/photo_audio_record.py` and playback in `/windows-version/screens/components.py` (`AudioPlayer`).

**Requirements:**
- Configure `AVAudioSession` with `.playAndRecord` category.
- **Recording:** Use `AVAudioRecorder` with settings: **AAC (`kAudioFormatMPEG4AAC`)**, 44.1 kHz, 1 channel, 64–96 kbps. Support a maximum duration of 30 seconds and a timer callback for UI updates.
- **Format note:** M4A (AAC) is used instead of WAV to reduce file size. `AVAudioRecorder` encodes AAC in hardware natively.
- **Playback:** Use `AVAudioPlayer` initialized with a file URL. Support stopping and restarting.
- Store temporary recordings in the app's `tmp` directory.

---

### 5.4 TCPClientService

**Responsibility:** Manage a persistent TCP connection to the ESP32-S3, send lock/unlock commands, receive status/heartbeat/events, and expose diagnostics.

**Protocol Specification:**
- **Framing:** Single ASCII byte per message (`'0'`–`'F'`). TCP is a stream; parse byte-by-byte.
- **iPad → ESP32 Commands:**

| Code | Action |
|------|--------|
| `'0'` | Heartbeat (auto-sent every 1 s if idle) |
| `'1'` | Lock |
| `'2'` | Unlock |
| `'3'`–`'F'` | Reserved |

- **ESP32 → iPad Status / Events:**

| Code | Meaning |
|------|---------|
| `'0'` | Heartbeat |
| `'1'` | State: Locked |
| `'2'` | State: Unlocked |
| `'3'` | Enter Home View (BOOT button pressed) |
| `'4'`–`'F'` | Reserved |

**Requirements:**
- Hardcoded endpoint: `192.168.0.100:8080`.
- Use `NWConnection` from `Network.framework`.
- Maintain connection while app is foregrounded; reconnect with exponential backoff (max ~5 s) on drop.
- Heartbeat: auto-send `'0'` every 1 s if no other command sent.
- RX: read bytes into a buffer, validate ASCII `'0'`–`'F'`, discard invalid bytes.
- Published diagnostics: `ConnectionState`, `lastRx`, `lastTx`, `fpsHistory` (5 s rolling), `errorLog` (last 20), `rawHexDump` (last 10 bytes), `localIPAddress`.
- Methods: `start()`, `stop()`, `send(_:)`, `forceReconnect()`.
- Thread-safe: use a dedicated `DispatchQueue` for all `NWConnection` I/O; publish to main queue.

---

## 6. Views / Screens

Implement the following 9 screens, matching the original screen flow in `/windows-version/main.py`:

```
Home
├── Choose Interact Type
│   ├── Deposit Flow
│   │   ├── Input Name
│   │   ├── Photo + Audio
│   │   └── Open Door
│   ├── Take Flow
│   │   ├── Select Item (grid)
│   │   ├── View Deposit Info
│   │   └── Open Door
│   └── Happy Memories
│       ├── Gallery (grid)
│       └── Detail (side-by-side)
```

Use a simple `NavigationStack` or custom navigation state object to manage transitions. Do not over-engineer animations.

### 6.1 HomeView

**Reference:** `/windows-version/screens/home_page.py` (`HomePage` + `ChooseInteractType`)

**Requirements:**
- Display a simple layout with the koala logo/door image and welcome text.
- A simple "Start" button (or tap anywhere) advances to the mode-selection view.
  - **Receiving `'3'` from the ESP32 also advances from welcome to mode-selection.**
- Mode-selection view shows three simple buttons/tappable areas:
  1. **Deposit**
  2. **Take**
  3. **Happy Memories**
- Tapping an option sets a shared navigation/app state (`mode`) and pushes the first screen of that flow.
- **Debug button:** A small `ant.fill` SF Symbol button, no border or background color, placed at the bottom-left corner. Tapping it presents `DebugView` as a sheet.
- **Audio cues (mapped from `/windows-version/main.py`):**
  - Play `start_interact.m4a` when transitioning from the welcome screen to the mode-selection view.
  - Play `meet_people.m4a` when the user taps **Deposit** or **Take**.
  - Play `goodbye.m4a` when a flow completes and the app returns to `HomeView`.
- **Keep it minimal.** No complex custom layouts. A `VStack` or `HStack` of buttons is sufficient.

### 6.2 DepositFlow / InputNameView

**Reference:** `/windows-version/screens/deposit/input_item_name.py`

**Requirements:**
- A single `TextField` for entering the item name.
- **Use the native iPadOS keyboard.** Do NOT build a custom keyboard.
- A "Next" button that validates:
  - Name is not empty.
  - A folder `data/{name}` does not already exist (duplicate check).
- If invalid, show a simple alert (`alert` modifier in SwiftUI).
- On success, pass the name to `PhotoAudioView` and set `mode = deposit`.

### 6.3 DepositFlow / PhotoAudioView

**Reference:** `/windows-version/screens/deposit/photo_audio_record.py`

**Requirements:**
- **Left side:** Live camera preview (using `CameraService` / `AVCaptureVideoPreviewLayer`).
  - Button to toggle preview on/off.
  - When preview is active, tapping capture saves a temporary photo.
- **Right side:** Audio recording controls.
  - Button to start/stop recording.
  - Label showing recording duration (e.g., "Recording... 5s").
  - Maximum duration: 60 seconds.
- **Bottom:** "Next" button.
- On "Next":
  1. Create `data/{item_name}/` folder.
  2. Move the captured photo (or copy `default_photo.png` if none captured) to `data/{item_name}/{item_name}_deposit_photo.jpg`.
  3. Move the recorded audio (or copy `default_audio.m4a` if none recorded) to `data/{item_name}/{item_name}_deposit_audio.m4a`.
  4. Call `insertDeposit` in GRDB with the final paths.
  5. Clear temporary files.
  6. Navigate to `OpenDoorView` with `mode = deposit`.

**Default fallback behavior (port from `/windows-version/screens/deposit/photo_audio_record.py`):**
- If the user proceeds without taking a photo, copy the bundled `default_photo.png` into the item folder.
- If the user proceeds without recording audio, copy the bundled `default_audio.m4a` into the item folder.

### 6.4 DepositFlow / OpenDoorView

**Reference:** `/windows-version/screens/deposit/open_door.py`

**Requirements:**
- Display a simple screen with a door image and instruction text.
- The text and title adapt based on `mode`:
  - **Deposit:** "Open the door to store the item."
  - **Take:** "Open the door to retrieve the item."
- **"Open Door" button:** Sends `'2'` (unlock) to the ESP32 via `TCPClientService`.
  - **Audio cue:** Play `open_door.m4a` concurrently with sending the TCP `'2'` unlock command (ported from `open_door.wav` in `/windows-version/main.py`).
- The user places/retrieves the item.
- **"Done" button:** Sends `'1'` (lock) to the ESP32, then:
  - If `mode == deposit`, return to the root/Home view.
  - If `mode == take`, navigate to `PhotoAudioView` (so the user can record retrieval photo/audio).
- The ESP32 handles the door timer internally; no iPad-side timer required.

### 6.5 TakeFlow / SelectItemView

**Reference:** `/windows-version/screens/take/select_take_item.py`

**Requirements:**
- A scrollable grid showing all **unretrieved** items (use `LazyVGrid`, 4 columns).
- Each cell shows:
  - The deposit photo (validated to exist on disk).
  - The item name below it.
- Tapping a cell loads the item details and navigates to `ViewDepositView`.
- A simple "Back" button to return to Home.

### 6.6 TakeFlow / ViewDepositView

**Reference:** `/windows-version/screens/take/view_deposit_info.py`

**Requirements:**
- Display the deposit photo (`AsyncImage` or `Image` loading from local file URL).
- Show item name and deposit timestamp.
- A tappable area/button to play the deposit audio (via `AudioService`).
- "Back" button → returns to `SelectItemView`.
- "Select / Take" button → sets the current item in app state, navigates to `OpenDoorView` with `mode = take`.

### 6.7 Memories / GalleryView

**Reference:** `/windows-version/screens/memories/select_memories.py`

**Requirements:**
- A scrollable grid (`LazyVGrid`, 4 columns) showing items where **both deposit and taken photos exist**.
- Each cell shows the **taken** photo (retrieval photo) and the item name.
- Tapping a cell navigates to `DetailView`.
- "Back" button to Home.

### 6.8 Memories / DetailView

**Reference:** `/windows-version/screens/memories/view_memories_details.py`

**Requirements:**
- Two-column layout:
  - **Left:** Deposit photo + deposit timestamp + "Play Deposit Audio" button.
  - **Right:** Taken photo + taken timestamp + "Play Taken Audio" button.
- Title bar shows the item name.
- "Back" button returns to `GalleryView`.
- Play buttons load the respective audio files via `AudioService`.

---

### 6.9 DebugView

**Reference:** PoC `DebugView.swift`

**Requirements:**
- Accessible via the `ant.fill` debug button on `HomeView` (presented as a sheet so it does not pollute the `NavigationStack` path).
- Displays the following diagnostics:
  - **Connection State Machine:** Colored indicator + text (`Disconnected`, `Connecting`, `Connected`, `Reconnecting`, etc.).
  - **Last RX / TX:** Character, hex value (`0x30`–`0x46`), and timestamp (`HH:mm:ss.SSS`).
  - **Frame Counter & FPS:** Bar chart showing valid frames received per second over the last 5 seconds.
  - **Raw Packet Hex Dump:** Last 10 bytes received in hex format.
  - **Network Vitals:** Local IP address, target IP (`192.168.0.100`), target port (`8080`).
  - **Force Reconnect:** Button to close the socket and immediately reconnect.
  - **Error Log:** Append-only list of the last 20 errors (TCP drops, parse errors, timeouts).
  - **Manual Command Injector:** Grid of 16 buttons (`0`–`F`). Tapping sends that character immediately.
- Use standard SwiftUI components (`ScrollView`, `LazyVGrid`, `Grid`). No custom canvas drawing.

---

## 7. Shared Components

### 7.1 YellowBar

**Reference:** `/windows-version/screens/components.py` (`YellowBar`, `YellowTitleBar`)

**Requirements:**
- A simple horizontal bar with a yellow background (`Color.yellow`).
- Contains a title label in Poppins font.
- `YellowTitleBar` variant also includes a "Back" button on the left.
- **Keep minimal.** No custom canvas drawing, no shadow effects. Use SwiftUI `Rectangle()` or `.background()` modifiers.

### 7.2 RoundedButton

**Reference:** `/windows-version/screens/components.py` (`RoundedButton`)

**Requirements:**
- A simple button with black background, white text, and rounded corners.
- Use Poppins font.
- Implement as a reusable SwiftUI `View` modifier or wrapper around `Button`.

---

## 8. App State / Navigation

The original Kivy `ScreenManager` maintains shared state. Replace this with a simple `@Observable` or `ObservableObject` app state class:

```
AppState (shared)
├── currentItem: Item?           # Currently selected item for Take/Memories flows
├── mode: Mode?                  # .deposit or .take
├── tcpClient: TCPClientService  # Shared ESP32 TCP connection (§5.4)
└── navigationPath: NavigationPath
```

**Screen flow logic (port from `/windows-version/main.py`):**
- `MyScreenManager.switch_to(screenName, mode)` → push corresponding view + set `appState.mode`.
- `current_item` dictionary → strongly typed `AppState.currentItem`.

---

## 9. Assets to Migrate

Ingest the following assets from the repo root `/assets/` folder into the Xcode asset catalog or resource bundle:

| Asset | Usage |
|-------|-------|
| `deposit.png`, `take.png`, `happy.png` | Home screen mode icons |
| `door_open.png`, `door_close.png` | OpenDoorView visuals |
| `simple_logo.png` | Branding |
| `default_photo.png` | Fallback when user skips photo |
| `default_audio.m4a` | Fallback when user skips audio recording (ported from `default_audio.wav` in `/windows-version/screens/deposit/photo_audio_record.py`) |
| `open_door.m4a` | Played when the "Open Door" button is tapped in `OpenDoorView` (ported from `open_door.wav` in `/windows-version/main.py`) |
| `goodbye.m4a` | Played when returning to `HomeView` at the end of a session (ported from `goodbye.wav` in `/windows-version/main.py`) |
| `start_interact.m4a` | Played when advancing from welcome to mode-selection in `HomeView` (ported from `start_interact.wav` in `/windows-version/main.py`) |
| `meet_people.m4a` | Played when the user begins a Deposit or Take flow (ported from `meet_people.wav` in `/windows-version/main.py`) |
| `Microphone.png` | Recording status icon |
| `Trumpet.png` | Audio play button icon |
| `Poppins/` (all TTF files) | Required brand font |

**Audio cue mapping (ported from `/windows-version/main.py`):**
In the original Python app, these sounds were triggered by external hardware events. In the iPad rewrite they are played locally by `AudioService` at the equivalent lifecycle moments:
- `start_interact.m4a` (original `start_interact.wav`) → Play when the user first engages (welcome → mode-selection transition).
- `meet_people.m4a` (original `meet_people.wav`) → Play when the user selects Deposit or Take.
- `open_door.m4a` (original `open_door.wav`) → Play on the "Open Door" button tap in `OpenDoorView` (before or concurrently with the TCP `'2'` unlock command).
- `goodbye.m4a` (original `goodbye.wav`) → Play when the flow completes and the app navigates back to `HomeView`.

---

## 10. Non-Functional Requirements

1. **iPad-only.** Target iPadOS 17+.
2. **Orientation:** Support both landscape and portrait (the original app is landscape-oriented; ensure layouts adapt).
3. **Permissions:** Add `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, and **`NSLocalNetworkUsageDescription`** to `Info.plist`.
4. **Network Capability:** Ensure `Network.framework` is linked and the app has the local-network entitlement.
5. **Font registration:** Add all Poppins TTF files to the app target and list them under `UIAppFonts` in `Info.plist`.
6. **Error handling:** Log errors to console (matching original `print` debugging style). Do not build elaborate error UI beyond simple alerts.

---

## 11. Implementation Order (Revised)

| Step | Task | Rationale |
|------|------|-----------|
| 1 | **Project setup:** Xcode project + GRDB (SPM) + `Info.plist` permissions (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, **`NSLocalNetworkUsageDescription`**) + ingest all assets/fonts + register Poppins in `UIAppFonts` + **link `Network.framework`** | Foundation and legal requirements for hardware and local network access; fonts must be ready before any view renders. |
| 2 | **Shared components:** `YellowBar`, `YellowTitleBar`, `RoundedButton`, Poppins `Font` extensions | These are primitives used by virtually every screen, not "polish." Building views without them forces refactoring later. |
| 3 | **Persistence layer:** `DatabaseService` + `Item` model + `ItemStore` CRUD + file I/O (`saveFile`, fallback copy logic) + unit tests | Core logic verified in isolation. Define an error-handling contract here (`Result` or `throws`) so `CameraService`, `AudioService`, and `TCPClientService` follow the same pattern. |
| 4 | **Audio service:** `AVAudioRecorder` + `AVAudioPlayer` wrapper (M4A/AAC) | Self-contained and easier than camera; builds confidence before tackling harder services. |
| 5 | **TCP client service:** `Network.framework` `NWConnection` wrapper (`TCPClientService`), heartbeat, auto-reconnect, protocol models (`PayloadRecord`, `LogEntry`, `ConnectionState`), debug view layout | Must exist before `HomeView` (Step 7) so the `'3'` command handler and `ant.fill` debug button have a service to bind to. |
| 6 | **Camera service:** `AVCaptureSession` + `AVCapturePhotoOutput` + **`UIViewRepresentable` preview bridge** | Hardest service. The `UIViewRepresentable` wrapper for `AVCaptureVideoPreviewLayer` is non-trivial and must be treated as a first-class engineering task, not an afterthought. Debug with a simple scratch view before integrating into the deposit flow. |
| 7 | **Navigation + Home:** `NavigationStack`, `AppState`, `HomeView` (with `ant.fill` debug sheet button + `'3'` ESP32 command handler), `InputNameView` | Establish routing and the root view before building deeper flows. |
| 8 | **Deposit flow:** `PhotoAudioView` → `OpenDoorView` (now functional: sends `'2'` unlock / `'1'` lock via `TCPClientService`) | First real integration of camera + audio + TCP services. |
| 9 | **Take flow:** `SelectItemView` → `ViewDepositView` | Depends on database + file validation already proven in step 3. |
| 10 | **Memories flow:** `GalleryView` → `DetailView` | Read-only flow; safe to build last. |
| 11 | **End-to-end testing & iPad optimization:** Physical device testing, rotation handling, TCP reconnection stress test, ESP32 fail-safe validation, memory profiling | Validate the camera bridge, audio session interruptions, TCP reconnect behavior, and gallery scrolling performance on real hardware. |

---

## 12. ESP32-S3 Firmware Specification

**Target:** ESP32-S3-N16R8 (Arduino IDE board target: `ESP32S3 Dev Module`)

### 12.1 Network Configuration (Hardcoded)

| Parameter | Value |
|-----------|-------|
| SSID | `Optus_A0516A` |
| Password | `lakes95962ca` |
| Static IP | `192.168.0.100` |
| Gateway | `192.168.0.1` |
| Subnet | `255.255.255.0` |
| DNS | `192.168.0.1` |
| TCP Listen Port | `8080` |

### 12.2 Protocol (Rearranged)

**iPad → ESP32 Commands:**

| Code | Action |
|------|--------|
| `'0'` | Heartbeat |
| `'1'` | Lock |
| `'2'` | Unlock |
| `'3'`–`'F'` | Reserved |

**ESP32 → iPad Status / Events:**

| Code | Meaning |
|------|---------|
| `'0'` | Heartbeat |
| `'1'` | State: Locked |
| `'2'` | State: Unlocked |
| `'3'` | Enter Home View (BOOT button pressed) |
| `'4'`–`'F'` | Reserved |

### 12.3 Core Loop Behavior

- **Heartbeat:** If no transmission in the last **1 s**, send `'0'` to iPad.
- **Fail-safe:** If no valid command for **300 s**, set state to `LOCKED` and send `'1'` to iPad.
- **BOOT button (GPIO0):** Debounced press sends `'3'` to iPad.
- **RGB LED (GPIO48):** Action indicator using Adafruit NeoPixel.
  - Receives `'1'` (lock) → **red** for 1 s.
  - Receives `'2'` (unlock) → **green** for 1 s.
  - Receives `'0'` → no LED change.
  - Receives any other valid command → **blue** for 1 s.
  - All LED durations are non-blocking (`millis()`-based).

### 12.4 Requirements

- Fully non-blocking main loop (no `delay()`).
- Use `WiFiServer` / `WiFiClient` from ESP32 Arduino core.
- `tcpServer.setNoDelay(true)` for low-latency single-byte frames.
- Maintain exactly one TCP client connection.
- Parse TCP stream byte-by-byte; validate ASCII `'0'`–`'F'`.

---
