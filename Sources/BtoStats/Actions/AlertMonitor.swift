import Foundation
import UserNotifications

/// Dispara una notificación nativa cuando una métrica CRUZA a nivel crítico
/// (transición no-crítico → crítico). Debounce por métrica: no re-notifica
/// hasta que baje del crítico o pasen 5 minutos. OFF por defecto (opt-in).
final class AlertMonitor {
    private var wasCritical: [MetricID: Bool] = [:]
    private var lastNotified: [MetricID: TimeInterval] = [:]
    private let cooldown: TimeInterval = 300
    private var authorized = false

    /// Pide permiso de notificaciones (solo funciona en la app empaquetada).
    func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    /// Llamar en cada tick con los valores crudos actuales.
    func check(store: MetricStore, now: TimeInterval) {
        guard AppConfig.shared.alertsEnabled else { return }

        evaluate(.cpu, store.cpu?.totalUsage, "CPU alta", store, now)
        evaluate(.memory, store.memory?.fractionUsed, "Memoria alta", store, now)
        evaluate(.temperature, store.sensors?.cpuTempAvg, "Temperatura alta", store, now)
        evaluate(.gpu, store.gpu?.utilization, "GPU alta", store, now)
        evaluate(.diskFree, store.disk.map { Double($0.availableBytes) }, "Disco casi lleno", store, now)
    }

    private func evaluate(_ metric: MetricID, _ value: Double?, _ title: String,
                          _ store: MetricStore, _ now: TimeInterval) {
        guard let value else { return }
        let critical = MetricThresholds.level(for: metric, value: value) == .critical
        let previouslyCritical = wasCritical[metric] ?? false
        wasCritical[metric] = critical

        guard critical, !previouslyCritical else { return }
        if let last = lastNotified[metric], now - last < cooldown { return }
        lastNotified[metric] = now
        notify(title: title, body: detail(for: metric, store: store))
    }

    private func detail(for metric: MetricID, store: MetricStore) -> String {
        switch metric {
        case .cpu: return String(format: "CPU al %.0f%%", (store.cpu?.totalUsage ?? 0) * 100)
        case .memory: return String(format: "RAM al %.0f%%", (store.memory?.fractionUsed ?? 0) * 100)
        case .temperature: return String(format: "CPU a %.0f °C", store.sensors?.cpuTempAvg ?? 0)
        case .gpu: return String(format: "GPU al %.0f%%", store.gpu?.utilization ?? 0)
        case .diskFree: return "Queda \(StatusItemController.bytes(store.disk?.availableBytes ?? 0)) libre"
        default: return ""
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
