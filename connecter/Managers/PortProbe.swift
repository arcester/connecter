import Foundation

/// Checks whether a TCP port on a host accepts connections.
///
/// Uses a plain BSD socket with a non-blocking `connect` and a `poll` timeout,
/// so it works inside the App Sandbox (`com.apple.security.network.client`)
/// without spawning external tools such as `nc`.
enum PortProbe {

    /// Default SMB port.
    nonisolated static let smbPort: UInt16 = 445

    /// Returns `true` if `host:port` accepted a TCP connection within `timeout`.
    nonisolated static func isOpen(
        host: String,
        port: UInt16 = smbPort,
        timeout: TimeInterval = 3
    ) async -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await Task.detached(priority: .userInitiated) {
            connectBlocking(host: trimmed, port: port, timeout: timeout)
        }.value
    }

    // MARK: - Private

    /// Resolves `host` and tries every address in turn until one accepts.
    private nonisolated static func connectBlocking(
        host: String, port: UInt16, timeout: TimeInterval
    ) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else {
            return false
        }
        defer { freeaddrinfo(list) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            if tryConnect(info.pointee, timeout: timeout) { return true }
            current = info.pointee.ai_next
        }
        return false
    }

    /// Non-blocking connect to a single resolved address.
    private nonisolated static func tryConnect(_ info: addrinfo, timeout: TimeInterval) -> Bool {
        let fd = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        if connect(fd, info.ai_addr, info.ai_addrlen) == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) > 0,
              pfd.revents & Int16(POLLOUT) != 0
        else { return false }

        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return false }
        return error == 0
    }
}
