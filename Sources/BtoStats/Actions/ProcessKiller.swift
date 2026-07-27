import AppKit

/// Terminar procesos. Sin privilegios solo se puede matar procesos del propio
/// usuario (cubre el caso real: apps colgadas y glotonas corren con tu uid).
/// Apps GUI: terminate() manda Quit Apple Event (respeta "¿guardar cambios?");
/// forceTerminate()/SIGKILL solo como segunda decisión explícita del usuario.
enum ProcessKiller {
    enum Outcome {
        case requested          // señal/quit enviado
        case notPermitted       // proceso de otro usuario (requiere helper admin, fase 8)
        case failed(String)
    }

    /// uid del dueño del proceso vía sysctl (visible sin privilegios).
    static func ownerUID(of pid: Int32) -> uid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid
    }

    static func canTerminate(pid: Int32) -> Bool {
        ownerUID(of: pid) == getuid()
    }

    static func terminate(pid: Int32, force: Bool) -> Outcome {
        guard canTerminate(pid: pid) else { return .notPermitted }

        if let app = NSRunningApplication(processIdentifier: pid) {
            let sent = force ? app.forceTerminate() : app.terminate()
            return sent ? .requested : .failed("la app rechazó la petición de cierre")
        }
        if kill(pid, force ? SIGKILL : SIGTERM) == 0 {
            return .requested
        }
        return .failed(String(cString: strerror(errno)))
    }
}
