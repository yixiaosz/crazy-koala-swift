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
│   ├── TCPClientService.swift       # NWConnection + ESP32 protocol (§5.4)
│   └── SessionLogService.swift      # Per-session timestamped action logging (§5.5)
├── Views/
│   ├── HomeView.swift               # Landing screen + mode selection + End Session (§6.1)
│   ├── PromptView.swift             # Reusable transition screen before PhotoAudioView (§6.2a, §6.2b)
│   ├── DepositFlow/
│   │   ├── InputNameView.swift      # Text input for item name
│   │   ├── PhotoAudioView.swift     # Camera preview + audio recording
│   │   └── OpenDoorView.swift       # Door-open instruction screen
│   ├── TakeFlow/
│   │   ├── SelectItemView.swift     # Grid of unretrieved items
│   │   └── ViewDepositView.swift    # Deposit detail before retrieval
│   ├── Memories/
│   │   ├── GalleryView.swift        # Grid of completed memories
│   │   └── DetailView.swift         # Side-by-side deposit/take detail
│   └── Debug/
│       ├── DebugView.swift          # ESP32 diagnostics + Session Logs entrance (§6.9)
│       ├── SessionLogsView.swift    # List of all session log files (§6.10)
│       └── SessionLogDetailView.swift # Full log content viewer (§6.10)
├── Components/
│   ├── YellowBar.swift              # Simple yellow header bar
│   └── RoundedButton.swift          # Simple button with corner radius
├── Assets/
│   ├── fonts/
│   │   └── Poppins/                 # TTF files from /assets/fonts/
│   ├── images/                      # PNG assets from /assets/
│   └── sounds/                      # Audio assets (all M4A/AAC)
└── Tests/
    └── ItemStoreTests.swift         # Unit tests for persistence layer (§4, §5.5)

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

**Date format handling (Critical):** SQLite's `DEFAULT CURRENT_TIMESTAMP` stores timestamps as **TEXT** in `"YYYY-MM-DD HH:MM:SS"` format. GRDB's default `Date` encoding uses `timeIntervalSinceReferenceDate` (a `Double`), which is **incompatible**. To avoid data corruption or decoding failures, configure a `DateFormatter` with format `"yyyy-MM-dd HH:mm:ss"` and register it as the database's date decoding/encoding strategy when setting up the `DatabaseQueue`. All `Date` properties in the `Item` struct must round-trip correctly through this format.

**Display timezone:** Timestamps are stored in UTC. When displaying timestamps to the user (e.g., in `ViewDepositView`, `DetailView`), use a separate `displayDateFormatter` configured with `TimeZone.current` (device local time) to convert from UTC to the local timezone.

### 4.2 CRUD Operations (Port from `/windows-version/database/db_operations.py`)

Implement the following operations in `ItemStore.swift`:

1. **`insertDeposit(name: String, depositPhotoPath: String?, depositAudioPath: String?)`**
   - Insert a new row with deposit paths.

2. **`updateTaken(itemId: Int64, takenPhotoPath: String?, takenAudioPath: String?)`**
   - Update the row matching `id` (primary key), setting `taken_photo_path`, `taken_audio_path`, and `taken_created_at = CURRENT_TIMESTAMP`.
   - **Uses `id` instead of `name`** because the `name` column has no `UNIQUE` constraint. Matching by name could update multiple rows if duplicates exist. The `id` is obtained from `AppState.currentItem` during the Take flow.

3. **`fetchAllItems() -> [Item]`**
   - Query rows where both `deposit_photo_path` and `taken_photo_path` are not NULL.
   - **Critical:** Validate that both photo files actually exist on disk using `FileManager`. Skip and log any rows with missing files. This behavior is identical to the current Python implementation.

4. **`fetchUnretrievedItems() -> [(name: String, photoPath: String)]`**
   - Query rows where `taken_created_at IS NULL`.
   - Validate that `deposit_photo_path` exists on disk. Return only valid items.

5. **`fetchItemDetails(name: String) -> Item?`**
   - Fetch a single row by name (`LIMIT 1`). Only deposit-related fields (`id`, `name`, `deposit_photo_path`, `deposit_audio_path`, `deposit_created_at`) are used by the caller; taken columns are expected to be `NULL` for unretrieved items.
   - Return nil if not found.
   - **Matches original:** `/windows-version/database/db_operations.py` `fetch_item_details()` only selects deposit columns. The Swift version may `SELECT *` for GRDB mapping convenience, but callers (e.g., `ViewDepositView`) must only display deposit fields.

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

**Path storage rule (Critical):** All paths stored in the database must be **relative to the `Documents/` directory** (e.g., `data/{item_name}/{item_name}_deposit_photo.jpg`). Never store absolute paths. The iOS sandbox container UUID can change across reinstalls and updates, which would break absolute paths. At runtime, resolve relative paths by prepending `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!`.

**Validation rule:** Never trust paths stored in the database alone. Always verify with `FileManager.default.fileExists(atPath:)` (using the resolved absolute path) before displaying or returning an item. This matches the current `os.path.exists` validation in `/windows-version/database/db_operations.py`.

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
- **Permission handling:** On first use, check `AVCaptureDevice.authorizationStatus(for: .video)`. If `.denied` or `.restricted`, show an alert explaining that camera access is required for the app to function, with a button to open Settings (`UIApplication.openSettingsURLString`). If the user proceeds without granting permission, gracefully fall back to using `default_photo.png` for all captures.

### 5.3 AudioService

**Responsibility:** Record audio to **M4A (AAC)** and play back audio files.

**Reference:** Audio logic in `/windows-version/screens/deposit/photo_audio_record.py` and playback in `/windows-version/screens/components.py` (`AudioPlayer`).

**Requirements:**
- Configure `AVAudioSession` with `.playAndRecord` category.
- **Recording:** Use `AVAudioRecorder` with settings: **AAC (`kAudioFormatMPEG4AAC`)**, 44.1 kHz, 1 channel, 64–96 kbps. Support a maximum duration of 60 seconds and a timer callback for UI updates.
- **Format note:** M4A (AAC) is used instead of WAV to reduce file size. `AVAudioRecorder` encodes AAC in hardware natively.
- **Playback:** Use `AVAudioPlayer` initialized with a file URL. Support stopping and restarting.
- Store temporary recordings in the app's `tmp` directory.
- **Permission handling:** On first use, check `AVAudioSession.sharedInstance().recordPermission`. If `.denied`, show an alert explaining that microphone access is required, with a button to open Settings. If the user proceeds without granting permission, gracefully fall back to using `default_audio.m4a` for all recordings.

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
- Methods: `start()`, `stop()`, `send(_:)`, `forceReconnect()`, `sendLockAndVerify(timeout: TimeInterval, retries: Int, completion: @escaping (Bool) -> Void)`.
- **Lock ACK verification (`sendLockAndVerify`):** Sends `'1'` (lock), then waits for the ESP32 to respond with `'1'` (state: locked) within the specified timeout (default 2 s). If no `'1'` response is received, retries once. If the retry also times out, calls completion with `false` so the caller can display a warning to the user. Used by the **End Session** flow (§6.1) as a safety-critical operation.
- Thread-safe: use a dedicated `DispatchQueue` for all `NWConnection` I/O; publish to main queue.

---

### 5.5 SessionLogService

**Responsibility:** Create one timestamped plain-text log file per user session, immediately append every user action to disk, and recover gracefully if the app is killed mid-session.

**Session Definition:**
- **Start:** User enters the mode-selection view (via welcome-screen tap or ESP32 `'3'`).
- **End:** User taps the **"End Session"** button.
- **Rule:** If a session is already active, ESP32 `'3'` is ignored.

**Log File Format:**
- **Location:** `Documents/logs/session_YYYY-MM-DD_HH-mm-ss_SSS.txt`
- **Encoding:** UTF-8, one line per entry.
- **Timestamp:** Millisecond precision — `yyyy-MM-dd HH:mm:ss.SSS`.
- **Line format:** `[timestamp] [ACTION] key=value key=value ...`

**Logged Actions (Exhaustive):**

| Action | Trigger | Details |
|--------|---------|---------|
| `SESSION_START` | Enter mode selection | `trigger`: `tap_start` / `esp32_button` |
| `SELECT_MODE` | Tap Deposit / Take / Memories | `mode`: `deposit` / `take` / `memories` |
| `VIEW_APPEAR` | `onAppear` of any flow view | `view`: `InputNameView`, `PhotoAudioView`, etc. |
| `INPUT_NAME` | Tap Next after typing | `name`: user input value |
| `CAPTURE_PHOTO` | Photo captured | `path`: file path |
| `RECORD_AUDIO_START` | Tap record | — |
| `RECORD_AUDIO_STOP` | Tap stop / auto-stop at 60 s | `duration_ms` |
| `PLAY_AUDIO` | Tap play button | `file`: filename |
| `TAP_NEXT` | Tap Next | `from`: current view |
| `TAP_BACK` | Tap Back | `from`: current view |
| `TAP_DONE` | Tap Done in `OpenDoorView` | `from`: `OpenDoorView`, `mode` |
| `DOOR_UNLOCK` | Tap "Open Door" / send TCP `'2'` | — |
| `DOOR_LOCK` | Tap "Done" after placing item / send TCP `'1'` | — |
| `SELECT_ITEM` | Tap item in grid | `name`: item name |
| `ESP32_TX` | Send any TCP command | `code`, `meaning` |
| `ESP32_RX` | Receive any TCP event | `code`, `meaning` |
| `ERROR` | Any thrown error / alert shown | `message` |
| `SESSION_END` | Tap "End Session" | `duration_ms` |
| `SESSION_ABORTED` | App killed/crashed before `SESSION_END` | `reason`: `app_killed_or_crash` |

**Crash / Kill Resilience:**
1. Every `log()` call appends to the file **immediately** via `FileHandle` on a background queue. No in-memory buffering.
2. On `startSession()`, store the active log file URL in `UserDefaults` under key `activeSessionLogURL`.
3. On app launch, `SessionLogService` checks `UserDefaults`:
   - If a URL exists and the file does not end with `SESSION_END`, append `SESSION_ABORTED` with the current timestamp.
   - Clear the `UserDefaults` key.
4. On normal `endSession()`, write `SESSION_END`, then clear the `UserDefaults` key.

**Interface:**
```swift
class SessionLogService {
    func startSession(trigger: SessionTrigger)
    func log(_ action: LogAction, details: [String: String]? = nil)
    func endSession()
    var isSessionActive: Bool { get }
    var currentLogURL: URL? { get }
}
```

---

## 6. Views / Screens

Implement the following screens, matching the original screen flow in `/windows-version/main.py`, plus developer-only debug screens:

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
│   │   ├── Open Door
│   │   └── Photo + Audio (reuses shared PhotoAudioView in take mode)
│   └── Happy Memories
│       ├── Gallery (grid)
│       └── Detail (side-by-side)
```

Use a simple `NavigationStack` or custom navigation state object to manage transitions. Do not over-engineer animations.

### 6.1 HomeView

**Reference:** `/windows-version/screens/home_page.py` (`HomePage` + `ChooseInteractType`)

**Two States:**
1. **Welcome screen** — shown at app launch and after a session ends.
2. **Mode-selection view** — shown during an active session.

**Requirements:**
- **Welcome screen:** `HStack` layout — `door_close` image on the **left**, text and button on the **right** (left-aligned).
  - **Image:** `door_close`, max height 500pt.
  - **Text:** "Connect to Our \nCommunity \nTogether\n" (Poppins Bold, 48pt) followed by "for Better Future" (Poppins Regular, 42pt).
  - **Button:** "Press Koala's Nose to Start" — advances to the mode-selection view.
  - **Receiving `'3'` from the ESP32 also advances from welcome to mode-selection, but only if no session is currently active.**
  - On transition to mode-selection, call `SessionLogService.startSession(trigger:)`.
- **Mode-selection view:** Shows three simple buttons/tappable areas (each with a 200×200pt icon and Poppins Bold 32pt label):
  1. **Deposit**
  2. **Take**
  3. **Happy Memories**
  - Tapping an option sets a shared navigation/app state (`mode`) and pushes the first screen of that flow.
  - **End Session button:** A clearly visible button (e.g., red-outlined pill) on the mode-selection view. Tapping it:
    1. Calls `SessionLogService.endSession()`.
    2. Sends lock with ACK verification via `TCPClientService.sendLockAndVerify(timeout: 2, retries: 1)` (§5.4). If the ACK is not received after the retry, display a warning alert (e.g., "Door lock could not be confirmed. Please verify manually.") but still proceed to step 3.
    3. Plays `goodbye.m4a`.
    4. Returns to the welcome screen.
- **Debug button:** A small `ant.fill` SF Symbol button, no border or background color, placed at the bottom-left corner **of the welcome screen only**. Tapping it presents `DebugView` as a sheet. This ensures developers can access diagnostics and session logs **without starting a session**.
- **Audio cues (mapped from `/windows-version/main.py`):**
  - Play `start_interact.m4a` when transitioning from the welcome screen to the mode-selection view.
  - ~~Play `meet_people.m4a` when the user taps **Deposit** or **Take**.~~ **Removed:** `meet_people.m4a` is intended for the robot's obstacle avoidance scenario, not for mode selection. It is no longer played in the app.
  - Play `goodbye.m4a` **only when the user taps End Session** (not on flow completion).
- **Keep it minimal.** No complex custom layouts. A `VStack` or `HStack` of buttons is sufficient.

### 6.2 DepositFlow / InputNameView

**Reference:** `/windows-version/screens/deposit/input_item_name.py`

**Requirements:**
- A single `TextField` for entering the item name.
- **Use the native iPadOS keyboard.** Do NOT build a custom keyboard.
- A "Next" button that validates:
  - Name is not empty (after trimming leading/trailing whitespace).
  - Name contains only allowed characters: **alphanumeric, spaces, hyphens, and underscores**. Reject any name containing `/`, `\`, `..`, `:`, or other filesystem-unsafe characters.
  - Name does not exceed **50 characters**.
  - A folder `data/{name}` does not already exist (duplicate check).
- If invalid, show a simple alert (`alert` modifier in SwiftUI) with a specific message for each validation failure.
- Prompt text: "Enter a name\nfor the item you would like to deposit".
- On success, pass the name to **DepositPromptView** (transition screen) and set `mode = deposit`.

### 6.2a DepositPromptView (Transition Screen)

**Purpose:** Shown between `InputNameView` and `PhotoAudioView` in the deposit flow.

**Requirements:**
- Display message: "Give your item a personal touch — add a photo or record a quick audio message."
- A "Continue" button navigates to `PhotoAudioView`.
- A "Back" button returns to `InputNameView`.

### 6.2b TakePromptView (Transition Screen)

**Purpose:** Shown between `OpenDoorView` (take mode) and `PhotoAudioView` in the take flow.

**Requirements:**
- Display message: "A photo or voice note for the item you're taking? It'll be saved to the Happy Memories."
- A "Continue" button navigates to `PhotoAudioView`.
- A "Back" button returns to the previous screen.

**Implementation:** Both prompts are implemented as a single reusable `PromptView` with configurable `message` and `destination` parameters.

### 6.3 Shared / PhotoAudioView

**Reference:** `/windows-version/screens/deposit/photo_audio_record.py`

**Requirements:**
- **Left side:** Live camera preview (using `CameraService` / `AVCaptureVideoPreviewLayer`).
  - Button to toggle preview on/off.
  - When preview is active, tapping capture saves a temporary photo.
- **Right side:** Audio recording controls.
  - Button to start/stop recording.
  - Label showing recording duration (e.g., "Recording... 5s").
  - Maximum duration: 60 seconds.
- **Bottom:** "Back" button and "Next" button.
  - **Back button:** Discards any temporary photo/audio files, stops the camera session and any active recording, and navigates back to the previous screen (`InputNameView` in deposit mode, `ViewDepositView` in take mode). Does **not** modify the database or create any folders.
- **Deposit mode** (`mode == deposit`) — On "Next":
  1. Create `data/{item_name}/` folder.
  2. Move the captured photo (or copy `default_photo.png` if none captured) to `data/{item_name}/{item_name}_deposit_photo.jpg`.
  3. Move the recorded audio (or copy `default_audio.m4a` if none recorded) to `data/{item_name}/{item_name}_deposit_audio.m4a`.
  4. Call `insertDeposit` in GRDB with the final paths.
  5. Clear temporary files.
  6. Navigate to `OpenDoorView` with `mode = deposit`.
  - **Rollback on failure:** If any step (1–4) fails, undo all prior steps: delete the `data/{item_name}/` folder and any files already moved into it, do not insert into the database, and show an error alert. The user remains on `PhotoAudioView` to retry. Log the error via `SessionLogService`.
- **Take mode** (`mode == take`) — On "Next":
  1. Move the captured photo (or copy `default_photo.png`) to `data/{item_name}/{item_name}_taken_photo.jpg`.
  2. Move the recorded audio (or copy `default_audio.m4a`) to `data/{item_name}/{item_name}_taken_audio.m4a`.
  3. Call `updateTaken` in GRDB with the item's `id` (from `AppState.currentItem`) and the final paths.
  4. Clear temporary files.
  5. Return to `HomeView` **mode-selection view** (session stays active).
  - **Rollback on failure:** If any step (1–3) fails, delete any taken photo/audio files already moved into the item folder, do not update the database, and show an error alert. The user remains on `PhotoAudioView` to retry. Log the error via `SessionLogService`.

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
  - **Disabled state:** The button must be **disabled** when `TCPClientService.connectionState != .connected`. Display a visible warning (e.g., "Cannot connect to the lock") below or near the button when disabled, so the user understands why the door cannot be opened.
  - **Audio cue:** Play `open_door.m4a` concurrently with sending the TCP `'2'` unlock command (ported from `open_door.wav` in `/windows-version/main.py`).
- The user places/retrieves the item.
- **"Done" button:** Sends `'1'` (lock) to the ESP32, then:
  - If `mode == deposit`, return to the `HomeView` **mode-selection view** (session stays active).
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
- **Audio button UX:** Only the button that is currently playing should show "Stop Audio". The other button remains in its default label. When playback finishes (naturally or by tapping stop), the button reverts immediately (no fade animation). If a different audio button is tapped while one is playing, the current playback stops and the new one starts.

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
  - **Session Logs:** Button that pushes/presents `SessionLogsView` (§6.10).
  - **Export All Data:** Button that creates a **zip archive** of the entire `Documents/data/` directory (all item folders with photos and audio) and presents a `UIActivityViewController` share sheet. Use `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)` to create the zip — this is a built-in iOS API that automatically zips a directory, no external dependencies required. The zip is created in a temporary location and cleaned up after sharing.
  - **Erase All Data:** Button (styled destructively, e.g., red text) that **deletes all user-generated data**. Requires a confirmation alert ("This will permanently delete all items, photos, audio recordings, and session logs. This cannot be undone."). On confirmation:
    1. Delete all contents of `Documents/data/` directory.
    2. Delete all rows from the `items` table in the database (or delete and recreate `items.db`).
    3. Delete all session log files in `Documents/logs/`.
    4. Clear any active session state (`SessionLogService`, `AppState.currentItem`).
    5. Return to the welcome screen.
  - **Note:** The app is designed for single-day use. After the event, developers use **Export All Data** to archive everything, then **Erase All Data** (or reinstall via Xcode) to reset for next use.
- Use standard SwiftUI components (`ScrollView`, `LazyVGrid`, `Grid`). No custom canvas drawing.

### 6.10 Debug / SessionLogsView & SessionLogDetailView

**Responsibility:** Allow developers to inspect, share, and delete per-session log files without exposing them to end users.

**SessionLogsView Requirements:**
- List all `.txt` files in `Documents/logs/`, sorted newest → oldest.
- Each row shows: filename, file size, line count (entry count), and parsed session duration (if start/end timestamps are present).
- **Tap row:** Push to `SessionLogDetailView` showing the full log text in a scrollable `Text` view (monospaced).
- **Share (single):** Each row has a share button → `UIActivityViewController` via `UIViewControllerRepresentable`. Uses iPadOS native share sheet.
- **Multi-select:** Edit mode → select multiple files → toolbar Share button → `UIActivityViewController` with multiple file URLs.
- **Delete:** Swipe-to-delete individual files, or multi-select bulk delete.
- **No auto-deletion:** Logs are kept indefinitely until manually deleted.

**SessionLogDetailView Requirements:**
- Scrollable monospaced text view displaying the full log content.
- Share button in navigation bar to export the single file.

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

### 7.3 BundleImage

**File:** `App/BundleImage.swift`

**Responsibility:** Load images from the app bundle (loose resource files in `Resources/Images/`), not from the Asset Catalog (`.xcassets`). SwiftUI's `Image("name")` only searches the Asset Catalog; `UIImage(named:)` searches both the Asset Catalog and the app bundle.

**Requirements:**
- Use `UIImage(named:)` to load the image, then wrap in `Image(uiImage:)`.
- Accept optional `maxWidth` and `maxHeight` for sizing.
- Show a placeholder SF Symbol (`photo`) if the image is not found.
- **All PNG assets** from `Resources/Images/` (e.g., `simple_logo`, `deposit`, `take`, `happy`, `door_open`, `door_close`, `Microphone`, `Trumpet`, `default_photo`) must be loaded via `BundleImage`, not `Image("name")`.

---

## 8. App State / Navigation

The original Kivy `ScreenManager` maintains shared state. Replace this with a simple `@Observable` or `ObservableObject` app state class:

```
AppState (shared)
├── currentItem: Item?           # Currently selected item for Take/Memories flows
├── mode: Mode?                  # .deposit, .take, or .memories
├── tcpClient: TCPClientService  # Shared ESP32 TCP connection (§5.4)
├── sessionLog: SessionLogService # Shared session logger (§5.5)
├── isSessionActive: Bool        # true when in mode-selection view or any flow
└── navigationPath: NavigationPath
```

**Screen flow logic (port from `/windows-version/main.py`):**
- `MyScreenManager.switch_to(screenName, mode)` → push corresponding view + set `appState.mode`.
- `current_item` dictionary → strongly typed `AppState.currentItem`.
- **Mode enum:** `Mode` must include `.deposit`, `.take`, and `.memories`. Set `.memories` when the user taps Happy Memories to avoid stale state from a previous Deposit or Take flow. Clear `mode` to `nil` when returning to the mode-selection view.
- **Session lifecycle:** `isSessionActive` is set to `true` on welcome→mode-selection transition, and `false` on End Session. If `isSessionActive == true`, ESP32 `'3'` is ignored.

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
| `goodbye.m4a` | Played **only when the user taps "End Session"** (ported from `goodbye.wav` in `/windows-version/main.py`) |
| `start_interact.m4a` | Played when advancing from welcome to mode-selection in `HomeView` (ported from `start_interact.wav` in `/windows-version/main.py`) |
| `meet_people.m4a` | **Not used in the iPad app.** Originally for the robot's obstacle avoidance. Kept in assets for potential future robot integration. |
| `Microphone.png` | Recording status icon |
| `Trumpet.png` | Audio play button icon |
| `Poppins/` (all TTF files) | Required brand font |

**Audio cue mapping (ported from `/windows-version/main.py`):**
In the original Python app, these sounds were triggered by external hardware events. In the iPad rewrite they are played locally by `AudioService` at the equivalent lifecycle moments:
- `start_interact.m4a` (original `start_interact.wav`) → Play when the user first engages (welcome → mode-selection transition).
- `meet_people.m4a` (original `meet_people.wav`) → **Not used.** Intended for robot obstacle avoidance, not mode selection.
- `open_door.m4a` (original `open_door.wav`) → Play on the "Open Door" button tap in `OpenDoorView` (before or concurrently with the TCP `'2'` unlock command).
- `goodbye.m4a` (original `goodbye.wav`) → Play **only when the user taps "End Session"** on the mode-selection view.

---

## 10. Non-Functional Requirements

1. **iPad-only.** Target iPadOS 17+.
2. **Orientation:** Support both landscape and portrait (the original app is landscape-oriented; ensure layouts adapt).
3. **Permissions:** Add `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, and **`NSLocalNetworkUsageDescription`** to `Info.plist`.
4. **Network Capability:** Ensure `Network.framework` is linked and the app has the local-network entitlement.
5. **Font registration:** Add all Poppins TTF files to the app target and list them under `UIAppFonts` in `Info.plist`.
6. **Error handling:** Log errors to console (matching original `print` debugging style). Do not build elaborate error UI beyond simple alerts.
7. **Log storage:** Session logs are stored in `Documents/logs/` inside the app sandbox. They are never automatically deleted. Developers access them via the hidden `SessionLogsView` inside `DebugView`.
8. **Kiosk deployment (Guided Access):** The app is designed to run as a kiosk. Deploy using **iPadOS Guided Access** (Settings → Accessibility → Guided Access) to lock the iPad into single-app mode. This prevents users from exiting the app, accessing Control Center, or triggering Notification Center. The dev plan assumes Guided Access is enabled in production; no in-app kiosk lockdown logic is required.
9. **App lifecycle handling:**
   - **Background transition:** Stop `AVCaptureSession` and any active `AVAudioRecorder` when the app enters background (`scenePhase == .inactive` or `.background`). Restart the camera session when returning to foreground if the user was on `PhotoAudioView`.
   - **Audio session interruption:** Observe `AVAudioSession.interruptionNotification`. If an interruption begins during recording, stop the recording gracefully and update the UI. If the interruption ends, do not auto-resume — let the user manually restart.
   - **TCP connection in background:** `NWConnection` will be suspended by iOS when the app is backgrounded. On return to foreground, check connection state and trigger reconnect if needed. With Guided Access enabled, backgrounding should not occur during normal use.
10. **Data export:** The app supports batch export of all item data (photos, audio) as a zip archive and full data erasure via the `DebugView` (§6.9). This is the primary mechanism for archiving event data before resetting the device.
11. **Light mode only.** Set `UIUserInterfaceStyle` to `Light` in `Info.plist`. The app does not adapt to dark mode.

---

## 11. Implementation Order

| Step | Task | Rationale |
|------|------|-----------|
| 1 | **Project setup:** Xcode project + GRDB (SPM) + `Info.plist` permissions (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, **`NSLocalNetworkUsageDescription`**) + ingest all assets/fonts + register Poppins in `UIAppFonts` + **link `Network.framework`** | Foundation and legal requirements for hardware and local network access; fonts must be ready before any view renders. |
| 2 | **Shared components:** `YellowBar`, `YellowTitleBar`, `RoundedButton`, Poppins `Font` extensions | These are primitives used by virtually every screen, not "polish." Building views without them forces refactoring later. |
| 3 | **Persistence layer:** `DatabaseService` + `Item` model + `ItemStore` CRUD + file I/O (`saveFile`, fallback copy logic) + **`SessionLogService`** (create log file, immediate disk append, `UserDefaults` crash recovery, `LogAction` enum) + unit tests | Core logic verified in isolation. `SessionLogService` is persistence-adjacent and must exist before any view that logs user actions. |
| 4 | **Audio service:** `AVAudioRecorder` + `AVAudioPlayer` wrapper (M4A/AAC) | Self-contained and easier than camera; builds confidence before tackling harder services. |
| 5 | **TCP client service + DebugView:** `Network.framework` `NWConnection` wrapper (`TCPClientService`), heartbeat, auto-reconnect, protocol models, `DebugView` layout, **`SessionLogsView`** + **`SessionLogDetailView`** + `UIActivityViewController` share sheet bridge | Must exist before `HomeView` (Step 7) so the `'3'` command handler and `ant.fill` debug button have a service to bind to. Session log viewer is built here because it is developer-only UI attached to DebugView. |
| 6 | **Camera service:** `AVCaptureSession` + `AVCapturePhotoOutput` + **`UIViewRepresentable` preview bridge** | Hardest service. The `UIViewRepresentable` wrapper for `AVCaptureVideoPreviewLayer` is non-trivial and must be treated as a first-class engineering task, not an afterthought. Debug with a simple scratch view before integrating into the deposit flow. |
| 7 | **Navigation + Home:** `NavigationStack`, `AppState` (with `isSessionActive`, `sessionLog`), `HomeView` (welcome + mode-selection states, **End Session button**, `ant.fill` debug sheet button, `'3'` ESP32 command handler with session-gate), `InputNameView` | Establish routing, root view, and session lifecycle. End Session button sends lock command and plays `goodbye.m4a`. Flows return to mode-selection, keeping the session alive. |
| 8 | **Deposit flow:** `PhotoAudioView` → `OpenDoorView` (now functional: sends `'2'` unlock / `'1'` lock via `TCPClientService`) | First real integration of camera + audio + TCP services. |
| 9 | **Take flow:** `SelectItemView` → `ViewDepositView` | Depends on database + file validation already proven in step 3. |
| 10 | **Memories flow:** `GalleryView` → `DetailView` | Read-only flow; safe to build last. |
| 11 | **End-to-end testing & iPad optimization:** Physical device testing, rotation handling, TCP reconnection stress test, ESP32 fail-safe validation, memory profiling | Validate the camera bridge, audio session interruptions, TCP reconnect behavior, and gallery scrolling performance on real hardware. |

---

## 12. ESP32-S3 Firmware Specification

**Target:** ESP32-S3-N16R8 (Arduino IDE board target: `ESP32S3 Dev Module`)

### 12.1 Network Configuration

| Parameter | Value |
|-----------|-------|
| SSID | `Optus_A0516A` |
| Password | `lakes95962ca` |
| Static IP | `192.168.0.100` |
| Gateway | `192.168.0.1` |
| Subnet | `255.255.255.0` |
| DNS | `192.168.0.1` |
| TCP Listen Port | `8080` |

### 12.2 Protocol

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
- **Command ACK:** Upon receiving `'1'` (lock) or `'2'` (unlock), the ESP32 must **immediately** send back the corresponding state code (`'1'` or `'2'`) as an acknowledgment before performing the action (e.g., LED feedback). This allows the iPad to verify that the command was received (see `sendLockAndVerify` in §5.4).
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
