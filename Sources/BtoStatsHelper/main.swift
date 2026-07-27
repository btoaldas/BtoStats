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
        // powermetrics con salida plist estructurada; una muestra corta.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["--samplers", "tasks", "--show-process-gpu",
                             "-i", "700", "-n", "1", "-f", "plist"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            reply(Data("[]".utf8)); return
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let tasks = root["tasks"] as? [[String: Any]] else {
            reply(Data("[]".utf8)); return
        }
        let rows: [[String: Any]] = tasks.compactMap { task in
            guard let pid = task["pid"] as? Int,
                  let name = task["name"] as? String else { return nil }
            let gpuMs = (task["gputime_ms_per_s"] as? Double)
                ?? (task["gputime_ns"] as? Double).map { $0 / 1_000_000 } ?? 0
            guard gpuMs > 0 else { return nil }
            return ["pid": pid, "name": name, "gpuMs": gpuMs]
        }
        .sorted { ($0["gpuMs"] as? Double ?? 0) > ($1["gpuMs"] as? Double ?? 0) }
        reply((try? JSONSerialization.data(withJSONObject: Array(rows.prefix(10)))) ?? Data("[]".utf8))
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
