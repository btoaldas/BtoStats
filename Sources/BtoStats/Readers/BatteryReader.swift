import Foundation
import IOKit
import IOKit.ps

/// Estado de la batería vía IOKit público (IOPowerSources + AppleSmartBattery).
/// Porcentaje, carga, tiempo restante, salud (ciclos, capacidad), watts.
/// Devuelve nil en equipos sin batería (Mac de escritorio).
final class BatteryReader {
    struct Snapshot {
        let percentage: Int
        let isCharging: Bool
        let timeRemainingMinutes: Int?   // nil = calculando
        let cycleCount: Int
        let healthPercent: Int           // capacidad máxima / diseño
        let watts: Double                // + carga, − descarga
        let temperatureC: Double?
    }

    func read() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        let percentage = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        var timeRemaining: Int? = desc[kIOPSTimeToEmptyKey] as? Int
        if charging { timeRemaining = desc[kIOPSTimeToFullChargeKey] as? Int }
        if let t = timeRemaining, t < 0 { timeRemaining = nil }

        let smart = Self.smartBattery()
        return Snapshot(percentage: percentage,
                        isCharging: charging,
                        timeRemainingMinutes: timeRemaining,
                        cycleCount: smart.cycles,
                        healthPercent: smart.health,
                        watts: smart.watts,
                        temperatureC: smart.temp)
    }

    /// Datos finos del IORegistry (AppleSmartBattery).
    private static func smartBattery() -> (cycles: Int, health: Int, watts: Double, temp: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (0, 0, 0, nil) }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return (0, 0, 0, nil) }

        let cycles = dict["CycleCount"] as? Int ?? 0
        // AppleRawMaxCapacity y DesignCapacity vienen en mAh; MaxCapacity suele
        // ser ya un porcentaje normalizado — no mezclarlos (daría ~1% absurdo).
        let designCap = dict["DesignCapacity"] as? Int ?? 0
        let health: Int
        if let rawMax = dict["AppleRawMaxCapacity"] as? Int, designCap > 0 {
            health = Int(Double(rawMax) / Double(designCap) * 100)
        } else if let pct = dict["MaxCapacity"] as? Int, pct <= 100 {
            health = pct
        } else {
            health = 0
        }

        let amperage = Double(dict["Amperage"] as? Int ?? 0)   // mA (con signo)
        let voltage = Double(dict["Voltage"] as? Int ?? 0)     // mV
        let watts = amperage / 1000 * voltage / 1000

        let temp = (dict["Temperature"] as? Int).map { Double($0) / 100 } // centi-°C
        return (cycles, min(health, 100), watts, temp)
    }
}
