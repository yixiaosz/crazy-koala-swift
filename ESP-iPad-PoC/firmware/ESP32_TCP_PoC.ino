/*
  ESP32-S3 ↔ iPad TCP Control Link — Proof-of-Concept Firmware
  Target: ESP32-S3-N16R8 (Arduino board: "ESP32S3 Dev Module")
  
  Features:
    - Wi-Fi STA with static IP
    - TCP server on port 8080 (single persistent client)
    - Single-byte ASCII command protocol ('0'–'F')
    - WS2812 RGB LED on GPIO48 (NeoPixel)
    - 1 Hz heartbeat (auto-TX '0' when idle)
    - 300 s fail-safe timer (locks placeholder state on comms loss)
    - Fully non-blocking (millis()-based scheduling)
*/

#include <WiFi.h>
#include <Adafruit_NeoPixel.h>

// ============================================================================
// 1. NETWORK CONFIGURATION — Edit these for your lab environment
// ============================================================================
const char* WIFI_SSID     = "Optus_A0516A";
const char* WIFI_PASSWORD = "lakes95962ca";

IPAddress STATIC_IP(192, 168, 0, 100);
IPAddress GATEWAY(192, 168, 0, 1);
IPAddress SUBNET(255, 255, 255, 0);
IPAddress DNS1(192, 168, 0, 1);   // Primary DNS (usually same as gateway)

const uint16_t TCP_PORT = 8080;

// ============================================================================
// 2. TIMING CONSTANTS — All times in milliseconds
// ============================================================================
const unsigned long HEARTBEAT_INTERVAL_MS = 1000UL;   // 1 s auto heartbeat
const unsigned long FAILSAFE_TIMEOUT_MS   = 300000UL; // 300 s comms-loss fail-safe

// ============================================================================
// 3. HARDWARE PINS
// ============================================================================
const uint8_t RGB_LED_PIN = 48;
const uint8_t NUM_RGB_LEDS = 1;
const uint8_t BOOT_BUTTON_PIN = 0;

const unsigned long LED_TEST_DURATION_MS = 1000UL;
const unsigned long BUTTON_DEBOUNCE_MS   = 50UL;

// ============================================================================
// 4. GLOBAL OBJECTS & STATE
// ============================================================================
Adafruit_NeoPixel rgbLED(NUM_RGB_LEDS, RGB_LED_PIN, NEO_GRB + NEO_KHZ800);

WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;

// Timing trackers
unsigned long lastTxTime      = 0;  // Last time we sent anything to iPad
unsigned long lastRxTime      = 0;  // Last time we received anything from iPad
unsigned long lastValidRxTime = 0;  // Last time we received a valid command byte

// Fail-safe / state machine
enum LockState { LOCKED, UNLOCKED, FAULT };
LockState lockState = LOCKED;   // Start conservative (locked)
bool failSafeTriggered = false;

// Connection tracking
bool clientWasConnected = false;

// LED test auto-reset (non-blocking)
bool ledTestActive = false;
unsigned long ledTestStartTime = 0;

// BOOT button state
bool bootButtonLastState = HIGH;
unsigned long bootButtonDebounceTime = 0;

// ============================================================================
// 5. SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) { ; }  // Wait for Serial up to 3 s
  Serial.println("\n========================================");
  Serial.println("ESP32-S3 TCP PoC Starting...");
  Serial.println("========================================");

  // --- Initialize RGB LED (off) ---
  rgbLED.begin();
  rgbLED.setBrightness(50);  // 0–255
  rgbLED.clear();
  rgbLED.show();
  Serial.println("[HW] RGB LED initialized on GPIO48");

  // --- Initialize BOOT button (GPIO0, active LOW, internal pull-up) ---
  pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
  Serial.println("[HW] BOOT button initialized on GPIO0");

  // --- Connect Wi-Fi with static IP ---
  WiFi.config(STATIC_IP, GATEWAY, SUBNET, DNS1);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("[WiFi] Connecting to ");
  Serial.print(WIFI_SSID);
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("[WiFi] Connected. IP = ");
  Serial.println(WiFi.localIP());

  // --- Start TCP server ---
  tcpServer.begin();
  tcpServer.setNoDelay(true);  // Disable Nagle for low-latency single-byte frames
  Serial.print("[TCP] Server listening on port ");
  Serial.println(TCP_PORT);

  // --- Initialize timers ---
  unsigned long now = millis();
  lastTxTime      = now;
  lastRxTime      = now;
  lastValidRxTime = now;

  Serial.println("[SYS] Setup complete. Entering main loop.");
}

// ============================================================================
// 6. MAIN LOOP — Fully non-blocking
// ============================================================================
void loop() {
  unsigned long now = millis();

  // --------------------------------------------------------------------------
  // 6.1 Accept or maintain one TCP client connection
  // --------------------------------------------------------------------------
  if (!tcpClient || !tcpClient.connected()) {
    if (clientWasConnected) {
      Serial.println("[TCP] Client disconnected.");
      clientWasConnected = false;
      tcpClient.stop();
    }
    // Poll for new client
    tcpClient = tcpServer.accept();
    if (tcpClient && tcpClient.connected()) {
      clientWasConnected = true;
      Serial.print("[TCP] Client connected from ");
      Serial.println(tcpClient.remoteIP());
      // Reset timers on fresh connection so we don't instantly fail-safe
      lastTxTime      = now;
      lastRxTime      = now;
      lastValidRxTime = now;
    }
  }

  // --------------------------------------------------------------------------
  // 6.2 Process incoming bytes (TCP stream → per-byte commands)
  // --------------------------------------------------------------------------
  if (tcpClient && tcpClient.connected() && tcpClient.available()) {
    while (tcpClient.available()) {
      int incoming = tcpClient.read();
      if (incoming < 0) break;

      char cmd = (char)incoming;
      lastRxTime = now;

      // Validate: must be ASCII '0'–'9' or 'A'–'F'
      bool valid = ((cmd >= '0' && cmd <= '9') || (cmd >= 'A' && cmd <= 'F'));

      if (valid) {
        lastValidRxTime = now;
        failSafeTriggered = false;  // Fresh valid command clears fail-safe
        handleCommand(cmd);
      } else {
        Serial.print("[RX] Ignored invalid byte: 0x");
        Serial.println(incoming, HEX);
      }
    }
  }

  // --------------------------------------------------------------------------
  // 6.3 Auto heartbeat TX: send '0' if we haven't transmitted in 1 second
  // --------------------------------------------------------------------------
  if (tcpClient && tcpClient.connected()) {
    if ((now - lastTxTime) >= HEARTBEAT_INTERVAL_MS) {
      sendByte('0');
      // Note: lastTxTime updated inside sendByte()
    }
  }

  // --------------------------------------------------------------------------
  // 6.4 Fail-safe timer: no valid RX for 300 s → lock
  // --------------------------------------------------------------------------
  if (!failSafeTriggered && (now - lastValidRxTime) >= FAILSAFE_TIMEOUT_MS) {
    failSafeTriggered = true;
    lockState = LOCKED;
    Serial.println("[FAILSAFE] No valid command for 300s. State -> LOCKED.");

    // Optional: notify iPad if connected
    if (tcpClient && tcpClient.connected()) {
      sendByte('2');  // State: Locked
    }
  }

  // --------------------------------------------------------------------------
  // 6.5 LED Test auto-reset (non-blocking)
  // --------------------------------------------------------------------------
  if (ledTestActive && (millis() - ledTestStartTime >= LED_TEST_DURATION_MS)) {
    ledTestActive = false;
    setLEDColor(0, 0, 0);
    Serial.println("[ACT] LED Test -> AUTO OFF");
  }

  // --------------------------------------------------------------------------
  // 6.6 BOOT button polling (active LOW, pull-up)
  // --------------------------------------------------------------------------
  bool bootButtonState = digitalRead(BOOT_BUTTON_PIN);
  if (bootButtonState == LOW && bootButtonLastState == HIGH &&
      (now - bootButtonDebounceTime) > BUTTON_DEBOUNCE_MS) {
    bootButtonDebounceTime = now;
    Serial.println("[ACT] BOOT button pressed -> sending '5'");
    sendByte('5');
  }
  bootButtonLastState = bootButtonState;

  // --------------------------------------------------------------------------
  // 6.7 Small yield so the WiFi stack can breathe (non-blocking)
  // --------------------------------------------------------------------------
  delay(1);
}

// ============================================================================
// 7. COMMAND HANDLER
// ============================================================================
void handleCommand(char cmd) {
  Serial.print("[RX] Command: ");
  Serial.print(cmd);
  Serial.print(" (0x");
  Serial.print((uint8_t)cmd, HEX);
  Serial.println(")");

  switch (cmd) {
    case '0':
      // Heartbeat — no action, timer already reset in loop()
      Serial.println("[ACT] Heartbeat received.");
      break;

    case '1':
      // LED Test — solid red, auto-off after 1 s (non-blocking)
      Serial.println("[ACT] LED Test -> START");
      setLEDColor(255, 0, 0);
      sendByte('1');  // LED Test Ack
      ledTestActive = true;
      ledTestStartTime = millis();
      break;

    case '2':
      // Lock (placeholder)
      Serial.println("[ACT] Command LOCK (placeholder, no HW action)");
      lockState = LOCKED;
      // No TX response required by spec for '2'/'3' in normal operation
      break;

    case '3':
      // Unlock (placeholder)
      Serial.println("[ACT] Command UNLOCK (placeholder, no HW action)");
      lockState = UNLOCKED;
      break;

    case '4':
      // Fault (placeholder)
      Serial.println("[ACT] Command FAULT (placeholder, no HW action)");
      lockState = FAULT;
      break;

    default:
      // '5'–'F' reserved — no action
      Serial.println("[ACT] Reserved command, no action.");
      break;
  }
}

// ============================================================================
// 8. HELPERS
// ============================================================================

// Send a single ASCII byte to the connected TCP client
void sendByte(char b) {
  if (tcpClient && tcpClient.connected()) {
    tcpClient.write((uint8_t)b);
    lastTxTime = millis();
    Serial.print("[TX] Sent: ");
    Serial.print(b);
    Serial.print(" (0x");
    Serial.print((uint8_t)b, HEX);
    Serial.println(")");
  }
}

// Set the on-board RGB LED to an R/G/B value (0–255 each)
void setLEDColor(uint8_t r, uint8_t g, uint8_t b) {
  rgbLED.setPixelColor(0, rgbLED.Color(r, g, b));
  rgbLED.show();
}
