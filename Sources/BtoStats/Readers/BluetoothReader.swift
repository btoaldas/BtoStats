import Foundation
import IOKit

/// Nivel de batería de dispositivos de entrada Bluetooth (mouse, teclado,
/// trackpad) vía IORegistry AppleDeviceManagementHIDEventService — público,
/// sin sudo. (AirPods usan otra pila y no aparecen aquí.)
final class BluetoothReader {
    struct Device {
        let name: String
        let batteryPercent: Int
    }

    func read() -> [Device] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [Device] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let battery = dict["BatteryPercent"] as? Int else { continue }
            let name = (dict["Product"] as? String) ?? "Dispositivo BT"
            devices.append(Device(name: name, batteryPercent: battery))
        }
        return devices
    }
}
