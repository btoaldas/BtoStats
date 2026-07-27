import SwiftUI
import ServiceManagement

/// Ventana de preferencias con pestañas: General (lo esencial, liviano) y
/// Avanzadas (extras opt-in — colores dinámicos, alertas, umbrales — que no
/// tocan la experiencia base).
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

    // Avanzadas (opt-in)
    @State private var dynamicColors: Bool = AppConfig.shared.dynamicColorsEnabled
    @State private var alertsEnabled: Bool = AppConfig.shared.alertsEnabled
    @State private var sparklines: Bool = AppConfig.shared.barSparklinesEnabled
    @State private var historyOn: Bool = AppConfig.shared.historyEnabled
    @State private var cpuWarn: Double = AppConfig.shared.threshold(.cpu, .warning) * 100
    @State private var cpuCrit: Double = AppConfig.shared.threshold(.cpu, .critical) * 100
    @State private var tempWarn: Double = AppConfig.shared.threshold(.temperature, .warning)
    @State private var tempCrit: Double = AppConfig.shared.threshold(.temperature, .critical)

    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gauge") }
            advancedTab
                .tabItem { Label("Avanzadas", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 440, height: 560)
        .padding(.top, 6)
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Celdas de la cuadrícula").font(.headline)
                Text("Activa las métricas que quieras ver; arrastra o usa las flechas para el orden.")
                    .font(.caption).foregroundStyle(.secondary)

                List {
                    ForEach(order) { metric in
                        HStack {
                            Toggle(metric.displayName, isOn: binding(for: metric))
                            Spacer()
                            Button { move(metric, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).disabled(order.first == metric)
                            Button { move(metric, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).disabled(order.last == metric)
                        }
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                        AppConfig.shared.metricOrder = order
                        AppConfig.shared.notifyChanged()
                    }
                }
                .frame(height: 220)

                Divider()

                Picker("Filas de la cuadrícula", selection: $rows) {
                    Text("2 (normal)").tag(2)
                    Text("3 (pequeña)").tag(3)
                    Text("4 (mini)").tag(4)
                }
                .pickerStyle(.segmented)
                .onChange(of: rows) { _, v in
                    AppConfig.shared.gridRows = v; AppConfig.shared.notifyChanged()
                }

                HStack {
                    Text("Refresco")
                    Slider(value: $interval, in: 1...5, step: 0.5) { editing in
                        if !editing { AppConfig.shared.fastInterval = interval; AppConfig.shared.notifyChanged() }
                    }
                    Text(String(format: "%.1f s", interval)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }

                Toggle("Mantener el panel abierto al hacer clic fuera (anclado)", isOn: $panelPinned)
                    .onChange(of: panelPinned) { _, v in AppConfig.shared.panelPinned = v }

                Divider()

                Toggle("Widget de escritorio (anillos en tiempo real)", isOn: $desktopWidgetOn)
                    .onChange(of: desktopWidgetOn) { _, v in
                        AppConfig.shared.desktopWidgetEnabled = v; AppConfig.shared.notifyChanged()
                    }
                if desktopWidgetOn {
                    Picker("Tamaño del widget", selection: $desktopWidgetSize) {
                        ForEach(AppConfig.DesktopWidgetSize.allCases) { s in Text(s.displayName).tag(s) }
                    }
                    .onChange(of: desktopWidgetSize) { _, v in
                        AppConfig.shared.desktopWidgetSize = v; AppConfig.shared.notifyChanged()
                    }
                }

                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .disabled(!isBundled)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard isBundled else { return }
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
            }
            .padding(20)
        }
    }

    // MARK: - Avanzadas (opt-in)

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Extras opcionales").font(.headline)
                Text("Estas funciones vienen apagadas para mantener la app liviana. Actívalas si las quieres.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Colores dinámicos en la barra", isOn: $dynamicColors)
                    .onChange(of: dynamicColors) { _, v in
                        AppConfig.shared.dynamicColorsEnabled = v; AppConfig.shared.notifyChanged()
                    }
                Text("El valor se pone amarillo al pasar el umbral de aviso y rojo al crítico.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Alertas (notificación al cruzar el umbral crítico)", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { _, v in
                        AppConfig.shared.alertsEnabled = v; AppConfig.shared.notifyChanged()
                    }

                Toggle("Mini-gráfica de CPU en la barra", isOn: $sparklines)
                    .onChange(of: sparklines) { _, v in
                        AppConfig.shared.barSparklinesEnabled = v; AppConfig.shared.notifyChanged()
                    }

                Toggle("Histórico persistente (gráficas de día/semana/mes)", isOn: $historyOn)
                    .onChange(of: historyOn) { _, v in
                        AppConfig.shared.historyEnabled = v; AppConfig.shared.notifyChanged()
                    }
                Text("Guarda una muestra por minuto en disco para ver tendencias largas en el panel → Avanzadas.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text("Umbrales").font(.headline)
                thresholdRow("CPU aviso", value: $cpuWarn, range: 10...100, unit: "%") {
                    AppConfig.shared.setThreshold(.cpu, .warning, cpuWarn / 100)
                }
                thresholdRow("CPU crítico", value: $cpuCrit, range: 10...100, unit: "%") {
                    AppConfig.shared.setThreshold(.cpu, .critical, cpuCrit / 100)
                }
                thresholdRow("Temp aviso", value: $tempWarn, range: 40...110, unit: "°C") {
                    AppConfig.shared.setThreshold(.temperature, .warning, tempWarn)
                }
                thresholdRow("Temp crítico", value: $tempCrit, range: 40...110, unit: "°C") {
                    AppConfig.shared.setThreshold(.temperature, .critical, tempCrit)
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
                Text("Ayudante privilegiado (pide tu contraseña una vez) para cerrar procesos de root (doble confirmación) y vaciar caché de disco.")
                    .font(.caption).foregroundStyle(.secondary)
                if !isBundled {
                    Text("Disponible cuando la app esté instalada como .app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let helperError { Text(helperError).font(.caption).foregroundStyle(.red) }
            }
            .padding(20)
        }
    }

    private func thresholdRow(_ label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, unit: String,
                              onCommit: @escaping () -> Void) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range) { editing in if !editing { onCommit() } }
            Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 54, alignment: .trailing)
        }
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
