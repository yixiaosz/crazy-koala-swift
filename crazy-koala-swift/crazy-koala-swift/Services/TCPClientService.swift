// Services/TCPClientService.swift
// NWConnection TCP client for ESP32-S3 communication (dev-plan §5.4)

import Combine
import Foundation
import Network

// MARK: - Protocol Models

struct PayloadRecord {
    let character: Character
    let timestamp: Date

    var description: String {
        "\(character) \(character.hexString)"
    }

    var timestampString: String {
        DateFormatter.hhmmssSSS.string(from: timestamp)
    }
}

struct TCPLogEntry: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date

    var displayText: String {
        "[\(DateFormatter.hhmmssSSS.string(from: timestamp))] \(message)"
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(after: TimeInterval)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.reconnecting(let a), .reconnecting(let b)):
            return a == b
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting(let delay): return "Reconnecting (\(String(format: "%.1f", delay))s)"
        }
    }
}

extension Character {
    var hexString: String {
        guard let ascii = self.asciiValue else { return "0x??" }
        return String(format: "0x%02X", ascii)
    }
}

extension DateFormatter {
    static let hhmmssSSS: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - TCPClientService

final class TCPClientService: ObservableObject {
    static let host = "192.168.0.100"
    static let port: UInt16 = 8080

    // MARK: - Published Diagnostics (§5.4)

    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastRx: PayloadRecord?
    @Published var lastTx: PayloadRecord?
    @Published var fpsHistory: [Int] = []
    @Published var errorLog: [TCPLogEntry] = []
    @Published var rawHexDump: [UInt8] = []
    @Published var localIPAddress: String = "—"

    /// Callback for received characters — used by AppState to handle ESP32 events (e.g., '3')
    var onReceive: ((Character) -> Void)?

    // MARK: - Private

    private var connection: NWConnection?
    private var heartbeatTimer: Timer?
    private var fpsTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?

    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 5.0

    private var lastTxTime = Date.distantPast
    private var frameCountThisSecond = 0

    private let queue = DispatchQueue(label: "com.crazykoala.tcpclient")

    // Lock verification state
    private var lockVerifyCompletion: ((Bool) -> Void)?
    private var lockVerifyTimer: Timer?

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            self?.performStart()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.performStop()
        }
    }

    func forceReconnect() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Send (§5.4)

    func send(_ character: Character) {
        guard let data = String(character).data(using: .ascii) else { return }
        let record = PayloadRecord(character: character, timestamp: Date())

        queue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logError("TX Error: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self?.lastTxTime = Date()
                        self?.lastTx = record
                    }
                }
            })
        }
    }

    // MARK: - Lock with ACK Verification (§5.4)

    /// Sends '1' (lock), waits for ESP32 to respond with '1' (state: locked).
    /// Retries once on timeout. Calls completion with false if both attempts fail.
    func sendLockAndVerify(timeout: TimeInterval = 2, retries: Int = 1, completion: @escaping (Bool) -> Void) {
        sendLockAttempt(timeout: timeout, retriesRemaining: retries, completion: completion)
    }

    private func sendLockAttempt(timeout: TimeInterval, retriesRemaining: Int, completion: @escaping (Bool) -> Void) {
        // Cancel any previous verification
        lockVerifyTimer?.invalidate()
        lockVerifyCompletion = nil

        lockVerifyCompletion = { [weak self] success in
            self?.lockVerifyTimer?.invalidate()
            self?.lockVerifyTimer = nil
            self?.lockVerifyCompletion = nil

            if success {
                completion(true)
            } else if retriesRemaining > 0 {
                print("[TCPClientService] Lock ACK timeout, retrying...")
                self?.sendLockAttempt(timeout: timeout, retriesRemaining: retriesRemaining - 1, completion: completion)
            } else {
                print("[TCPClientService] Lock ACK failed after all retries")
                completion(false)
            }
        }

        send("1")

        DispatchQueue.main.async { [weak self] in
            self?.lockVerifyTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                self?.lockVerifyCompletion?(false)
            }
        }
    }

    // MARK: - Private: Connection

    private func performStart() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        performStop(clearState: false)

        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        let endpoint = NWEndpoint.hostPort(
            host: .init(Self.host),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )

        let newConnection = NWConnection(to: endpoint, using: .tcp)
        self.connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.reconnectAttempt = 0
                DispatchQueue.main.async { self.connectionState = .connected }
                self.startReading()
                self.startHeartbeat()
                self.startFPSTimer()
                self.updateLocalIP()

            case .failed(let error):
                self.logError("Connection failed: \(error.localizedDescription)")
                self.performStop(clearState: false)
                self.scheduleReconnect()

            case .cancelled:
                DispatchQueue.main.async { self.connectionState = .disconnected }
                self.stopTimers()

            case .waiting(let error):
                self.logError("Waiting: \(error.localizedDescription)")

            default:
                break
            }
        }

        newConnection.start(queue: queue)
    }

    private func performStop(clearState: Bool = true) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopTimers()
        connection?.cancel()
        connection = nil
        if clearState {
            DispatchQueue.main.async { self.connectionState = .disconnected }
        }
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)

        DispatchQueue.main.async {
            self.connectionState = .reconnecting(after: delay)
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performStart()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - Private: Reading (byte-by-byte, §5.4)

    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.logError("RX Error: \(error.localizedDescription)")
                self.performStop(clearState: false)
                self.scheduleReconnect()
                return
            }

            if let data = content {
                for byte in data {
                    self.handleReceivedByte(byte)
                }
            }

            if isComplete {
                self.logError("Connection closed by remote")
                self.performStop(clearState: false)
                self.scheduleReconnect()
            } else {
                self.startReading()
            }
        }
    }

    private func handleReceivedByte(_ byte: UInt8) {
        let scalar = UnicodeScalar(byte)
        guard scalar.isASCII else {
            logError("Non-ASCII byte: 0x\(String(byte, radix: 16, uppercase: true))")
            return
        }

        let char = Character(scalar)
        let validChars = Set("0123456789ABCDEF")
        guard validChars.contains(char) else {
            logError("Invalid command byte: \(char.hexString)")
            return
        }

        let record = PayloadRecord(character: char, timestamp: Date())

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastRx = record
            self.rawHexDump.append(byte)
            if self.rawHexDump.count > 10 {
                self.rawHexDump.removeFirst()
            }
            self.frameCountThisSecond += 1

            // Check for lock ACK ('1' = state: locked)
            if char == "1", let completion = self.lockVerifyCompletion {
                completion(true)
            }

            // Notify observers (e.g., AppState for '3' command)
            self.onReceive?(char)
        }
    }

    // MARK: - Private: Timers

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastTxTime) >= 1.0 {
                    self.send("0")
                }
            }
        }
    }

    private func startFPSTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fpsTimer?.invalidate()
            self.fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.fpsHistory.append(self.frameCountThisSecond)
                if self.fpsHistory.count > 5 {
                    self.fpsHistory.removeFirst()
                }
                self.frameCountThisSecond = 0
            }
        }
    }

    private func stopTimers() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
            self?.fpsTimer?.invalidate()
            self?.fpsTimer = nil
        }
    }

    // MARK: - Private: Logging

    private func logError(_ message: String) {
        let entry = TCPLogEntry(message: message, timestamp: Date())
        DispatchQueue.main.async { [weak self] in
            self?.errorLog.append(entry)
            if (self?.errorLog.count ?? 0) > 20 {
                self?.errorLog.removeFirst()
            }
        }
        print("[TCPClientService] \(message)")
    }

    // MARK: - Private: Local IP

    private func updateLocalIP() {
        DispatchQueue.main.async { [weak self] in
            self?.localIPAddress = Self.getWiFiAddress() ?? "Unknown"
        }
    }

    private static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        &addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        address = String(cString: hostname)
                    }
                }
            }
            ptr = interface.ifa_next
        }
        freeifaddrs(ifaddr)
        return address
    }
}
