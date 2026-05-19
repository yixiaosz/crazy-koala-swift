import Foundation
import Network
import Combine

class TCPClient: ObservableObject {
    static let sharedHost = "192.168.0.100"
    static let sharedPort: UInt16 = 8080
    
    // MARK: - Published State
    @Published var state: ConnectionState = .disconnected
    @Published var lastRx: PayloadRecord?
    @Published var lastTx: PayloadRecord?
    @Published var fpsHistory: [Int] = []
    @Published var errorLog: [LogEntry] = []
    @Published var rawHexDump: [UInt8] = []
    @Published var localIPAddress: String = "—"
    
    // MARK: - Private
    private var connection: NWConnection?
    private var heartbeatTimer: Timer?
    private var fpsTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 5.0
    
    private var lastTxTime = Date.distantPast
    private var frameCountThisSecond = 0
    
    private let queue = DispatchQueue(label: "com.poc.tcpclient")
    
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
    
    func send(_ character: Character) {
        guard let data = String(character).data(using: .ascii) else { return }
        
        let record = PayloadRecord(character: character, timestamp: Date())
        
        queue.async { [weak self] in
            guard let self = self, let connection = self.connection else { return }
            
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error = error {
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
    
    // MARK: - Private Helpers
    private func performStart() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        performStop(clearState: false)
        
        DispatchQueue.main.async {
            self.state = .connecting
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: .init(TCPClient.sharedHost),
            port: NWEndpoint.Port(rawValue: TCPClient.sharedPort)!
        )
        
        let newConnection = NWConnection(to: endpoint, using: .tcp)
        self.connection = newConnection
        
        newConnection.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
            guard let self = self else { return }
            switch newState {
            case .ready:
                self.reconnectAttempt = 0
                DispatchQueue.main.async {
                    self.state = .connected
                }
                self.startReading()
                self.startHeartbeat()
                self.startFPSTimer()
                self.updateLocalIP()
                
            case .failed(let error):
                self.logError("Connection failed: \(error.localizedDescription)")
                self.performStop(clearState: false)
                self.scheduleReconnect()
                
            case .cancelled:
                DispatchQueue.main.async {
                    self.state = .disconnected
                }
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
            DispatchQueue.main.async {
                self.state = .disconnected
            }
        }
    }
    
    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        
        DispatchQueue.main.async {
            self.state = .reconnecting(after: delay)
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.start()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    // MARK: - Reading
    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
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
            } else if self.state == .connected {
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
        
        DispatchQueue.main.async {
            self.lastRx = record
            self.rawHexDump.append(byte)
            if self.rawHexDump.count > 10 {
                self.rawHexDump.removeFirst()
            }
            self.frameCountThisSecond += 1
        }
    }
    
    // MARK: - Timers
    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if Date().timeIntervalSince(self.lastTxTime) >= 1.0 {
                    self.send("0")
                }
            }
        }
    }
    
    private func startFPSTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fpsTimer?.invalidate()
            self.fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.fpsHistory.append(self.frameCountThisSecond)
                    if self.fpsHistory.count > 5 {
                        self.fpsHistory.removeFirst()
                    }
                    self.frameCountThisSecond = 0
                }
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
    
    // MARK: - Logging
    private func logError(_ message: String) {
        let entry = LogEntry(message: message, timestamp: Date())
        DispatchQueue.main.async { [weak self] in
            self?.errorLog.append(entry)
            if (self?.errorLog.count ?? 0) > 20 {
                self?.errorLog.removeFirst()
            }
        }
    }
    
    // MARK: - Local IP
    private func updateLocalIP() {
        DispatchQueue.main.async { [weak self] in
            self?.localIPAddress = self?.getWiFiAddress() ?? "Unknown"
        }
    }
    
    private func getWiFiAddress() -> String? {
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
