//
//  NetworkMonitor.swift
//  Verbal
//
//  Observes connectivity so the UI can stay usable offline and surface a
//  small "You're Offline" banner instead of bouncing the user to sign-in.
//

import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    /// True when the device currently has a usable network path.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
