import Foundation

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

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
    
    var displayText: String {
        "[\(DateFormatter.hhmmssSSS.string(from: timestamp))] \(message)"
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case resolving
    case connecting
    case connected
    case reconnecting(after: TimeInterval)
    
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.resolving, .resolving),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.reconnecting(let a), .reconnecting(let b)):
            return a == b
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .resolving:
            return "Resolving"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting(let delay):
            return "Reconnecting (\(String(format: "%.1f", delay))s)"
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
