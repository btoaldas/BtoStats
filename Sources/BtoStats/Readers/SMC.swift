import Foundation
import IOKit

/// Cliente SMC de SOLO LECTURA (temperaturas, ventiladores).
/// Estructura de llamada portada del enfoque de exelban/stats (proyecto de
/// terceros bajo licencia licencia permisiva; BtoStats es PolyForm Strict — ver LICENSE).
/// Deliberadamente sin métodos de escritura: escribir al SMC (control de
/// ventiladores) requiere root y puede causar sobrecalentamiento.
final class SMC {
    private var connection: io_connect_t = 0

    private enum Command: UInt8 {
        case readBytes = 5
        case readKeyFromIndex = 8
        case readKeyInfo = 9
    }

    private struct KeyData {
        struct Version {
            var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct PLimit {
            var version: UInt16 = 0, length: UInt16 = 0
            var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Version()
        var pLimitData = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                   (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - API

    /// Todas las claves del SMC (enumeración dinámica vía #KEY + índice).
    func allKeys() -> [String] {
        guard let countData = readRaw(key: Self.fourCC("#KEY")), countData.bytes.count >= 4 else {
            return []
        }
        let count = countData.bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count < 20_000 else { return [] }

        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<count {
            var input = KeyData()
            input.data8 = Command.readKeyFromIndex.rawValue
            input.data32 = index
            guard let output = call(&input) else { continue }
            keys.append(Self.keyString(output.key))
        }
        return keys
    }

    /// Tipo de dato de una clave ("flt ", "ui8 ", …) o nil si no existe.
    func keyType(_ key: String) -> String? {
        keyInfo(Self.fourCC(key)).map { Self.keyString($0.dataType) }
    }

    /// Valor Float de una clave tipo 'flt ' (little-endian en Apple Silicon).
    func float(_ key: String) -> Float? {
        guard let raw = readRaw(key: Self.fourCC(key)),
              raw.type == "flt ", raw.bytes.count >= 4 else { return nil }
        return raw.bytes.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }
    }

    /// Valor entero de claves ui8/ui16/ui32 (big-endian, convención SMC).
    func uint(_ key: String) -> UInt32? {
        guard let raw = readRaw(key: Self.fourCC(key)) else { return nil }
        switch raw.type {
        case "ui8 ": return raw.bytes.count >= 1 ? UInt32(raw.bytes[0]) : nil
        case "ui16": return raw.bytes.prefix(2).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        case "ui32": return raw.bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        default: return nil
        }
    }

    // MARK: - Interno

    private func keyInfo(_ key: UInt32) -> KeyData.KeyInfo? {
        var input = KeyData()
        input.key = key
        input.data8 = Command.readKeyInfo.rawValue
        return call(&input)?.keyInfo
    }

    private func readRaw(key: UInt32) -> (type: String, bytes: [UInt8])? {
        guard let info = keyInfo(key), info.dataSize > 0, info.dataSize <= 32 else { return nil }
        var input = KeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readBytes.rawValue
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(Int(info.dataSize)))
        }
        return (Self.keyString(info.dataType), bytes)
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection,
                                               2, // kSMCHandleYPCEvent
                                               &input,
                                               MemoryLayout<KeyData>.stride,
                                               &output,
                                               &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCC(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func keyString(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                     UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
