import Foundation
import ServiceManagement
import BtoStatsHelperShared

/// Cliente del helper privilegiado. El helper es OPCIONAL y OFF por defecto:
/// registrarlo pide una aprobación de administrador una sola vez.
final class HelperClient {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?

    private var service: SMAppService {
        SMAppService.daemon(plistName: "ec.bto.BtoStats.helper.plist")
    }

    var isInstalled: Bool { service.status == .enabled }

    /// Registra el daemon (prompt de admin la primera vez).
    func install() throws { try service.register() }

    /// Lo quita por completo.
    func uninstall() throws { try service.unregister() }

    private func proxy() -> BtoStatsHelperProtocol? {
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                                options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: BtoStatsHelperProtocol.self)
            newConnection.invalidationHandler = { [weak self] in self?.connection = nil }
            newConnection.interruptionHandler = { [weak self] in self?.connection = nil }
            newConnection.resume()
            connection = newConnection
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in } as? BtoStatsHelperProtocol
    }

    func topGPUProcesses(reply: @escaping ([(pid: Int32, name: String, gpuMs: Double)]) -> Void) {
        guard isInstalled, let proxy = proxy() else { reply([]); return }
        proxy.topGPUProcesses { data in
            let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            let rows = parsed.compactMap { row -> (Int32, String, Double)? in
                guard let pid = row["pid"] as? Int,
                      let name = row["name"] as? String,
                      let gpuMs = row["gpuMs"] as? Double else { return nil }
                return (Int32(pid), name, gpuMs)
            }
            DispatchQueue.main.async { reply(rows.map { (pid: $0.0, name: $0.1, gpuMs: $0.2) }) }
        }
    }

    /// Termina un proceso de cualquier usuario (root incluido) vía helper.
    func terminatePrivileged(pid: Int32, force: Bool, name: String,
                             reply: @escaping (String) -> Void) {
        guard isInstalled, let proxy = proxy() else { reply("helper no instalado"); return }
        proxy.terminateProcess(pid: pid, force: force, expectedName: name) { result in
            DispatchQueue.main.async { reply(result) }
        }
    }

    func purgeDiskCache(reply: @escaping (String) -> Void) {
        guard isInstalled, let proxy = proxy() else { reply("helper no instalado"); return }
        proxy.purgeDiskCache { result in DispatchQueue.main.async { reply(result) } }
    }
}
