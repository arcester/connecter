import Foundation
import Network

/// Observes system network reachability.
///
/// `MountManager` skips mount checks while offline and re-checks every share
/// as soon as connectivity comes back, instead of waiting for the next
/// (possibly backed-off) interval.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isAvailable = true

    /// Called on the main actor whenever availability flips.
    var onAvailabilityChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "es.guzman.connecter.network", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isAvailable != available else { return }
                self.isAvailable = available
                self.onAvailabilityChange?(available)
            }
        }
        monitor.start(queue: queue)
    }
}
