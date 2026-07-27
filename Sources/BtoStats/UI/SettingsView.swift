import SwiftUI
import ServiceManagement

/// Ventana de preferencias: checks por métrica, orden (arrastrar), cadencia
/// y arranque al iniciar sesión.
struct SettingsView: View {
    @State private var order: [MetricID] = AppConfig.shared.metricOrder
    @State private var disabled: Set<MetricID> = AppConfig.shared.disabledMetrics
    @State private var interval: Double = AppConfig.shared.fastInterval
    @State private var rows: Int = AppConfig.shared.gridRows
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    /// SMAppService requiere que la app corra como bundle .app (fase 6).
    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Celdas de la cuadrícula")
                .font(.headline)
            Text("Activa las métricas que quieras ver; arrastra para cambiar el orden. Se agrupan de a dos por columna.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(order) { metric in
                    Toggle(metric.displayName, isOn: binding(for: metric))
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    AppConfig.shared.metricOrder = order
                    AppConfig.shared.notifyChanged()
                }
            }
            .frame(height: 210)

            Divider()

            Picker("Filas de la cuadrícula", selection: $rows) {
                Text("2 (normal)").tag(2)
                Text("3 (letra más pequeña)").tag(3)
            }
            .pickerStyle(.segmented)
            .onChange(of: rows) { _, newValue in
                AppConfig.shared.gridRows = newValue
                AppConfig.shared.notifyChanged()
            }

            HStack {
                Text("Refresco")
                Slider(value: $interval, in: 1...5, step: 0.5) { editing in
                    if !editing {
                        AppConfig.shared.fastInterval = interval
                        AppConfig.shared.notifyChanged()
                    }
                }
                Text(String(format: "%.1f s", interval))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                .disabled(!isBundled)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard isBundled else { return }
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        launchError = nil
                    } catch {
                        launchError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if !isBundled {
                Text("Disponible cuando la app esté instalada como .app (fase de empaquetado).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func binding(for metric: MetricID) -> Binding<Bool> {
        Binding(
            get: { !disabled.contains(metric) },
            set: { enabled in
                if enabled { disabled.remove(metric) } else { disabled.insert(metric) }
                AppConfig.shared.setEnabled(metric, enabled)
                AppConfig.shared.notifyChanged()
            }
        )
    }
}
