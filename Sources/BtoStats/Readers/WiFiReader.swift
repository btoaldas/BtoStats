import Foundation
import CoreWLAN

/// Detalle del enlace Wi-Fi vía CoreWLAN (sin privilegios). Banda, canal,
/// señal (RSSI), ruido y SSID — para ver de un vistazo por qué la red va
/// lenta (p. ej. estar en 2.4 GHz).
final class WiFiReader {
    struct Snapshot {
        let ssid: String?
        let bandGHz: String        // "2.4", "5", "6" o "—"
        let channel: Int
        let rssiDBm: Int           // señal (más cerca de 0 = mejor)
        let noiseDBm: Int
        let txRateMbps: Double
        var signalQuality: Int {   // 0-100 aproximado a partir del RSSI
            let clamped = max(-100, min(-30, rssiDBm))
            return Int(Double(clamped + 100) / 70 * 100)
        }
    }

    func read() -> Snapshot? {
        guard let interface = CWWiFiClient.shared().interface(),
              interface.ssid() != nil || interface.rssiValue() != 0 else { return nil }

        let channel = interface.wlanChannel()
        let band: String
        switch channel?.channelBand {
        case .band2GHz: band = "2.4"
        case .band5GHz: band = "5"
        default:
            if #available(macOS 14.0, *), channel?.channelBand == .band6GHz { band = "6" }
            else { band = "—" }
        }
        return Snapshot(ssid: interface.ssid(),
                        bandGHz: band,
                        channel: channel?.channelNumber ?? 0,
                        rssiDBm: interface.rssiValue(),
                        noiseDBm: interface.noiseMeasurement(),
                        txRateMbps: interface.transmitRate())
    }
}
