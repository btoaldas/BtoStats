import SwiftUI
import ServiceManagement

/// Ventana de preferencias: checks por métrica, orden (arrastrar), cadencia
/// y arranque al iniciar sesión.
struct SettingsView: View {
    @State private var order: [MetricID] = AppConfig.shared.metricOrder
    @State private var disabled: Set<MetricID> = AppConfig.shared.disabledMetrics
    @State private var interval: Double = AppConfig.shared.fastInterval
    @State private var rows: Int = AppConfig.shared.gridRows
    @State private var panelPinned: Bool = AppConfig.shared.panelPinned
    @State private var desktopWidgetOn: Bool = AppConfig.shared.desktopWidgetEnabled
    @State private var desktopWidgetSize: AppConfig.DesktopWidgetSize = AppConfig.shared.desktopWidgetSize
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var helperInstalled: Bool = HelperClient.shared.isInstalled
    @State private var helperError: String?
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
                    HStack {
                        Toggle(metric.displayName, isOn: binding(for: metric))
                        Spacer()
                        Button { move(metric, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(order.first == metric)
                        Button { move(metric, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(order.last == metric)
                    }
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    AppConfig.shared.metricOrder = order
                    AppConfig.shared.notifyChanged()
                }
            }
            .frame(height: 230)

            Divider()

            Picker("Filas de la cuadrícula", selection: $rows) {
                Text("2 (normal)").tag(2)
                Text("3 (pequeña)").tag(3)
                Text("4 (mini)").tag(4)
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

            Toggle("Mantener el panel abierto al hacer clic fuera (anclado)", isOn: $panelPinned)
                .onChange(of: panelPinned) { _, pinned in
                    AppConfig.shared.panelPinned = pinned
                }

            Divider()

            Toggle("Widget de escritorio (anillos en tiempo real)", isOn: $desktopWidgetOn)
                .onChange(of: desktopWidgetOn) { _, enabled in
                    AppConfig.shared.desktopWidgetEnabled = enabled
                    AppConfig.shared.notifyChanged()
                }
            if desktopWidgetOn {
                Picker("Tamaño del widget", selection: $desktopWidgetSize) {
                    ForEach(AppConfig.DesktopWidgetSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .onChange(of: desktopWidgetSize) { _, newSize in
                    AppConfig.shared.desktopWidgetSize = newSize
                    AppConfig.shared.notifyChanged()
                }
                Text("Arrástralo por el fondo para ubicarlo; la posición se recuerda.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Divider()

            Toggle("Funciones de administrador (opcional)", isOn: $helperInstalled)
                .disabled(!isBundled)
                .onChange(of: helperInstalled) { _, enabled in
                    do {
                        if enabled { try HelperClient.shared.install() }
                        else { try HelperClient.shared.uninstall() }
                        helperError = nil
                    } catch {
                        helperError = error.localizedDescription
                        helperInstalled = HelperClient.shared.isInstalled
                    }
                }
            Text("Instala un ayudante privilegiado (pide tu contraseña una vez) para: GPU exacta por proceso, cerrar procesos de otros usuarios/root y vaciar caché de disco. Todo desde el panel, con confirmación.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isBundled {
                Text("Disponible cuando la app esté instalada como .app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let helperError {
                Text(helperError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func move(_ metric: MetricID, by offset: Int) {
        guard let index = order.firstIndex(of: metric) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        AppConfig.shared.metricOrder = order
        AppConfig.shared.notifyChanged()
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
