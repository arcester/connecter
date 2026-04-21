import Foundation
import Network

/// Observes system network reachability.
/// Used by MountManager to skip mount checks when there is no network connection.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isAvailable = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "es.guzman.connecter.network", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isAvailable = available
            }
        }
        monitor.start(queue: queue)
    }
}
