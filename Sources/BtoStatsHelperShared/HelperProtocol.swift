import Foundation

/// Contrato XPC entre la app y el helper privilegiado.
/// SOLO operaciones concretas y cerradas — nunca comandos arbitrarios.
@objc public protocol BtoStatsHelperProtocol {
    /// Versión del helper (sanity check de conexión).
    func version(reply: @escaping (String) -> Void)

    /// Top GPU exacto por proceso vía powermetrics (JSON: [{pid, name, gpuMs}]).
    func topGPUProcesses(reply: @escaping (Data) -> Void)

    /// Termina un proceso de CUALQUIER usuario. Verifica que el nombre actual
    /// del pid coincida con el esperado (anti pid-reuse) antes de la señal.
    func terminateProcess(pid: Int32, force: Bool, expectedName: String,
                          reply: @escaping (String) -> Void)

    /// /usr/sbin/purge — vaciar caché de disco (experimental; no libera
    /// memoria de apps).
    func purgeDiskCache(reply: @escaping (String) -> Void)
}

public enum HelperConstants {
    public static let machServiceName = "ec.bto.BtoStats.helper"
    public static let version = "1.0.0"
    /// Único cliente aceptado: la app instalada.
    public static let expectedClientPath = "/Applications/BtoStats.app/Contents/MacOS/BtoStats"
}
