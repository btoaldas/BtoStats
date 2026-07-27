import Foundation
import BtoStatsHelperShared

/// Daemon privilegiado de BtoStats (launchd, on-demand vía XPC).
/// Superficie mínima: 3 operaciones cerradas. Sin shell, sin rutas ni
/// argumentos arbitrarios del cliente.
final class HelperDelegate: NSObject, NSXPCListenerDelegate, BtoStatsHelperProtocol {

    // MARK: - Validación de cliente

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Validación por AUDIT TOKEN (no por PID, que sufre reuso/TOCTOU):
        // setCodeSigningRequirement evalúa el requirement contra el token del
        // peer dentro del kernel. Con hardened runtime + library validation el
        // binario legítimo no puede cargar código inyectado, así que exigir su
        // identidad de firma es suficiente. Requisito: mismo ejecutable ad hoc.
        let requirement = "identifier \"ec.bto.BtoStats\" and anchor apple generic"
            + " or identifier \"ec.bto.BtoStats\""
        if #available(macOS 13.0, *) {
            connection.setCodeSigningRequirement(requirement)
        }
        // Defensa en profundidad: además, la ruta del ejecutable del peer.
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(connection.processIdentifier, &buffer, UInt32(buffer.count)) > 0,
              String(cString: buffer) == HelperConstants.expectedClientPath else {
            NSLog("BtoStatsHelper: conexión rechazada")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: BtoStatsHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    /// Nombres de procesos del sistema que el helper NUNCA debe matar (matarlos
    /// cuelga o compromete la sesión). Defensa propia, además de la UI.
    private static let protectedNames: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "logind",
        "coreaudiod", "configd", "securityd", "syslogd", "opendirectoryd",
        "distnoted", "notifyd", "cfprefsd", "mds", "mds_stores", "diskarbitrationd",
        "powerd", "watchdogd", "systemstats", "UserEventAgent", "hidd",
    ]

    // MARK: - Operaciones

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func topGPUProcesses(reply: @escaping (Data) -> Void) {
        // No implementado a propósito: powermetrics NO expone tiempo de GPU por
        // proceso en Apple Silicon (verificado en M5 — cero campos gpu* en el
        // plist de tasks, ni como root). Se conserva en el protocolo por
        // compatibilidad; la app usa el top GPU aproximado sin helper.
        reply(Data("[]".utf8))
    }

    func terminateProcess(pid: Int32, force: Bool, expectedName: String,
                          reply: @escaping (String) -> Void) {
        guard pid > 1 else { reply("pid inválido"); return } // jamás launchd/init
        // expectedName vacío anularía el guard anti pid-reuse: rechazar.
        let expected = expectedName.trimmingCharacters(in: .whitespaces)
        guard expected.count >= 2 else { reply("nombre de proceso requerido"); return }
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            reply("el proceso ya no existe"); return
        }
        let actual = String(cString: buffer)
        // No matar procesos críticos del sistema.
        guard !Self.protectedNames.contains(actual) else {
            reply("\(actual) es un proceso crítico del sistema y no se puede cerrar"); return
        }
        guard actual == expected else {
            reply("el PID ahora pertenece a otro proceso (\(actual))"); return
        }
        reply(kill(pid, force ? SIGKILL : SIGTERM) == 0 ? "ok"
              : String(cString: strerror(errno)))
    }

    func purgeDiskCache(reply: @escaping (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            reply(process.terminationStatus == 0 ? "ok" : "purge falló (\(process.terminationStatus))")
        } catch {
            reply("no se pudo ejecutar purge")
        }
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
