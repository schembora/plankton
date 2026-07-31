//
//  ServerDiscovery.swift
//  Plankton
//
//  Finds Jellyfin servers on the local network via UDP broadcast.
//

import Foundation

/// A Jellyfin server that answered a discovery probe.
struct DiscoveredServer: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
}

enum ServerDiscovery {

    /// Broadcasts a probe and yields each server that answers within `duration`.
    /// Discovery is best-effort: failures just mean an empty result.
    static func discover(duration: Duration = .seconds(5)) -> AsyncStream<DiscoveredServer> {
        AsyncStream { continuation in
            let session = DiscoverySession(onServer: { continuation.yield($0) })
            let timeout = Task {
                try? await Task.sleep(for: duration)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                session.stop()
                timeout.cancel()
            }
            session.start()
        }
    }
}

/// One unconnected UDP socket probing `255.255.255.255:7359`. Raw sockets are
/// used deliberately: an unconnected socket receives replies from any sender,
/// and SO_BROADCAST permits the probe — neither is guaranteed higher up.
private final class DiscoverySession: @unchecked Sendable {

    private static let discoveryPort: UInt16 = 7359
    private static let probe = [UInt8]("who is JellyfinServer?".utf8)

    private let onServer: (DiscoveredServer) -> Void
    private let queue = DispatchQueue(label: "com.schembor.Plankton.discovery")

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var isStopped = false

    init(onServer: @escaping (DiscoveredServer) -> Void) {
        self.onServer = onServer
    }

    func start() {
        queue.async { self.open() }
    }

    func stop() {
        queue.async {
            self.isStopped = true
            self.readSource?.cancel()
        }
    }

    // MARK: - Socket

    private func open() {
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind an ephemeral port so the socket can receive replies.
        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            closeFD()
            return
        }

        sendProbe()
        // LAN probes are fire-and-forget; one repeat covers a dropped packet.
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !isStopped else { return }
            sendProbe()
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.receiveAvailable() }
        source.setCancelHandler { [weak self] in self?.closeFD() }
        source.resume()
        readSource = source
    }

    private func sendProbe() {
        var broadcast = sockaddr_in()
        broadcast.sin_family = sa_family_t(AF_INET)
        broadcast.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        broadcast.sin_port = Self.discoveryPort.bigEndian
        broadcast.sin_addr.s_addr = INADDR_BROADCAST

        _ = withUnsafePointer(to: &broadcast) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Self.probe.withUnsafeBufferPointer { payload in
                    sendto(socketFD, payload.baseAddress, payload.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func receiveAvailable() {
        var buffer = [UInt8](repeating: 0, count: 4096)

        while !isStopped {
            let count = recv(socketFD, &buffer, buffer.count, MSG_DONTWAIT)
            guard count > 0 else { return }

            if let server = Self.decode(Data(buffer[..<count])) {
                onServer(server)
            }
        }
    }

    private func closeFD() {
        guard socketFD >= 0 else { return }
        close(socketFD)
        socketFD = -1
    }

    // MARK: - Decoding

    private static func decode(_ data: Data) -> DiscoveredServer? {
        struct Payload: Decodable {
            let id: String?
            let name: String?
            let address: String?

            enum CodingKeys: String, CodingKey {
                case id = "Id"
                case name = "Name"
                case address = "Address"
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let address = payload.address,
              let url = URL(string: address)
        else { return nil }

        return DiscoveredServer(
            id: payload.id ?? url.absoluteString,
            name: payload.name ?? url.host ?? "Jellyfin Server",
            url: url
        )
    }
}
