import SwiftUI

/// Pestaña "Avanzadas" del panel: métricas extra opt-in (sistema, Wi-Fi, watts,
/// frecuencias, disco I/O…). Se llena por bloques; los que aún no aplican al
/// equipo se muestran como "—".
struct AdvancedPanelView: View {
    @ObservedObject var model: PanelModel
    var scale: Double = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Sistema") {
                    row("Encendido hace", uptimeText)
                    row("Carga (1·5·15 min)", String(format: "%.2f · %.2f · %.2f",
                        model.loadAverage.0, model.loadAverage.1, model.loadAverage.2))
                    row("Procesos", "\(model.processCount)")
                }
                if model.wifiActive {
                    section("Wi-Fi") {
                        row("Red", model.wifiSSID)
                        row("Banda · canal", "\(model.wifiBand) GHz · \(model.wifiChannel)")
                        row("Señal", "\(model.wifiRSSI) dBm (\(model.wifiQuality)%)")
                        row("Velocidad de enlace", String(format: "%.0f Mbps", model.wifiTxMbps))
                        if model.wifiBand == "2.4" {
                            Text("Estás en la banda 2.4 GHz (lenta y congestionada). Si el router tiene 5/6 GHz, conéctate a esa red para más velocidad.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                section("Memoria (detalle)") {
                    row("Comprimida", String(format: "%.1f GB", model.compressedGB))
                    row("Swap", model.swapTotalGB > 0
                        ? String(format: "%.2f / %.2f GB", model.swapUsedGB, model.swapTotalGB)
                        : "sin uso")
                }
            }
            .padding(16)
        }
    }

    private var uptimeText: String {
        let total = Int(model.uptimeSeconds)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        return "\(h)h \(m)m"
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(spacing: 4) { content() }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 13))
    }
}
