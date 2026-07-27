import Foundation

/// Red ↑↓ en bytes/s vía sysctl IFMIB_IFDATA por interfaz (ifmibdata.ifmd_data,
/// contadores if_data64 de 64 bits reales).
///
/// NO usar NET_RT_IFLIST2: en macOS 26 el kernel entrega esos contadores
/// truncados a 32 bits a binarios de terceros (verificado empíricamente:
/// coinciden con netstat módulo 2^32). La vía MIB coincide byte a byte.
/// Delta entre lecturas: la primera llamada devuelve nil.
final class NetworkReader {
    struct Snapshot {
        let uploadBps: Double
        let downloadBps: Double
        let totalUploadBytes: UInt64
        let totalDownloadBytes: UInt64
    }

    private var previous: (up: UInt64, down: UInt64, uptime: TimeInterval)?

    /// Interfaces virtuales/loopback que duplican o ensucian el total:
    /// lo (loopback), utun (VPN — el tráfico ya cuenta en la física),
    /// awdl/llw (AirDrop), gif/stf (túneles), bridge, ap (hotspot).
    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "gif", "stf", "bridge", "ap"]

    func read() -> Snapshot? {
        guard let totals = Self.interfaceTotals() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (totals.up, totals.down, now) }

        guard let previous, now > previous.uptime else { return nil }
        // Si desaparece una interfaz (dock/USB-Ethernet/tethering) la suma total
        // BAJA y el delta envolvería a ~2^64 → pico absurdo que arruina el
        // gráfico. Re-basar y saltar este tick.
        guard totals.up >= previous.up, totals.down >= previous.down else { return nil }
        let dt = now - previous.uptime
        let upDelta = totals.up - previous.up
        let downDelta = totals.down - previous.down
        return Snapshot(uploadBps: Double(upDelta) / dt,
                        downloadBps: Double(downDelta) / dt,
                        totalUploadBytes: totals.up,
                        totalDownloadBytes: totals.down)
    }

    private static func interfaceTotals() -> (up: UInt64, down: UInt64)? {
        guard let list = if_nameindex() else { return nil }
        defer { if_freenameindex(list) }

        var up: UInt64 = 0
        var down: UInt64 = 0
        var readAny = false
        var cursor = list
        while cursor.pointee.if_index != 0, cursor.pointee.if_name != nil {
            let name = String(cString: cursor.pointee.if_name)
            if !isExcluded(name: name),
               let data = mibData(interfaceIndex: Int32(cursor.pointee.if_index)) {
                up &+= data.ifi_obytes
                down &+= data.ifi_ibytes
                readAny = true
            }
            cursor = cursor.advanced(by: 1)
        }
        return readAny ? (up, down) : nil
    }

    private static func mibData(interfaceIndex: Int32) -> if_data64? {
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC,
                            IFMIB_IFDATA, interfaceIndex, IFDATA_GENERAL]
        var data = ifmibdata()
        var length = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, u_int(mib.count), &data, &length, nil, 0) == 0 else { return nil }
        return data.ifmd_data
    }

    private static func isExcluded(name: String) -> Bool {
        excludedPrefixes.contains { prefix in
            name.hasPrefix(prefix) && name.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
    }
}
