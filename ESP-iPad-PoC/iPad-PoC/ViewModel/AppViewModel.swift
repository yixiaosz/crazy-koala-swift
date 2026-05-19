import Foundation
import Combine

class AppViewModel: ObservableObject {
    @Published var isLedActive = false
    @Published var isBootSignalActive = false
    
    let tcpClient = TCPClient()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        tcpClient.$lastRx
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                guard let record = record else { return }
                if record.character == "1" {
                    self?.isLedActive = true
                } else if record.character == "5" {
                    self?.isBootSignalActive = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.isBootSignalActive = false
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func connect() {
        tcpClient.start()
    }
    
    func disconnect() {
        tcpClient.stop()
    }
    
    func sendCommand(_ character: Character) {
        tcpClient.send(character)
    }
    
    func forceReconnect() {
        tcpClient.forceReconnect()
    }
}
