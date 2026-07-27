import Foundation
import Combine
import CoreWLAN

/// Estado observable del panel grande. Se actualiza desde el hilo principal
/// en cada tick (métricas) y cada ~5 s (top procesos).
final class PanelModel: ObservableObject {
    @Published var cpuUsage: Double = 0            // 0-1
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var memoryFraction: Double = 0      // 0-1
    @Published var gpuUsage: Double = 0            // 0-100
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var fanRPM: [Double] = []
    @Published var uploadBps: Double = 0
    @Published var downloadBps: Double = 0
    @Published var diskAvailable: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var coreCount: Int = 0

    @Published var cpuHistory: [Double] = []       // 0-1
    @Published var gpuHistory: [Double] = []       // 0-100
    @Published var memoryHistory: [Double] = []    // 0-1
    @Published var uploadHistory: [Double] = []    // B/s
    @Published var downloadHistory: [Double] = []  // B/s
    @Published var windowCapacity: Int = 300       // puntos de la ventana (dominio X)
    @Published var linkSpeedText: String = "—"     // ancho de banda del enlace

    @Published var memoryPressure: MemoryAdvisor.Pressure = .normal
    @Published var lastGPUProcess: String?
    /// (proceso, % de muestras de la ventana en que fue el último en usar la GPU)
    @Published var topGPU: [(name: String, percent: Double)] = []
    /// Top GPU EXACTO (ms/s por proceso) — solo si el helper está instalado.
    @Published var topGPUExact: [(name: String, gpuMs: Double)] = []
    @Published var helperActive: Bool = false
    @Published var totalCPUPercent: Double = 0   // suma pcpu (100 = 1 core)
    // Avanzadas
    @Published var uptimeSeconds: Double = 0
    @Published var loadAverage: (Double, Double, Double) = (0, 0, 0)
    @Published var processCount: Int = 0
    @Published var swapUsedGB: Double = 0
    @Published var swapTotalGB: Double = 0
    @Published var compressedGB: Double = 0
    @Published var wifiSSID: String = "—"
    @Published var wifiBand: String = "—"
    @Published var wifiChannel: Int = 0
    @Published var wifiRSSI: Int = 0
    @Published var wifiQuality: Int = 0
    @Published var wifiTxMbps: Double = 0
    @Published var wifiActive: Bool = false

    @Published var topCPU: [ProcessReader.ProcessSample] = []
    @Published var topRAM: [ProcessReader.ProcessSample] = []
    @Published var topNetwork: [ProcessReader.ProcessSample] = []

    func refresh(from store: MetricStore) {
        if let cpu = store.cpu {
            cpuUsage = cpu.totalUsage
            coreCount = cpu.perCore.count
        }
        if let memory = store.memory {
            memoryUsedGB = memory.usedBytes / 1e9
            memoryTotalGB = memory.totalBytes / 1e9
            memoryFraction = memory.fractionUsed
        }
        if let pressure = MemoryAdvisor.currentPressure() {
            memoryPressure = pressure
        }
        if let gpu = store.gpu {
            gpuUsage = gpu.utilization
            lastGPUProcess = gpu.lastSubmitterName
        }
        if let sensors = store.sensors {
            cpuTemp = sensors.cpuTempAvg
            gpuTemp = sensors.gpuTempAvg
            fanRPM = sensors.fanRPM
        }
        if let network = store.network {
            uploadBps = network.uploadBps
            downloadBps = network.downloadBps
        }
        if let disk = store.disk {
            diskAvailable = disk.availableBytes
            diskTotal = disk.totalBytes
        }
        if let wifi = store.wifi {
            wifiActive = true
            wifiSSID = wifi.ssid ?? "(oculto)"
            wifiBand = wifi.bandGHz
            wifiChannel = wifi.channel
            wifiRSSI = wifi.rssiDBm
            wifiQuality = wifi.signalQuality
            wifiTxMbps = wifi.txRateMbps
        } else {
            wifiActive = false
        }
        if let sys = store.system {
            uptimeSeconds = sys.uptimeSeconds
            loadAverage = sys.loadAverage
            processCount = sys.processCount
            swapUsedGB = Double(sys.swapUsedBytes) / 1e9
            swapTotalGB = Double(sys.swapTotalBytes) / 1e9
            compressedGB = Double(sys.compressedBytes) / 1e9
        }
        let submitters = store.gpuSubmitterHistory.elements
        if !submitters.isEmpty {
            var counts: [String: Int] = [:]
            for name in submitters { counts[name, default: 0] += 1 }
            topGPU = counts
                .map { (name: $0.key, percent: Double($0.value) / Double(submitters.count) * 100) }
                .sorted { $0.percent > $1.percent }
                .prefix(8)
                .map { $0 }
        }
        let seconds = AppConfig.shared.chartWindowSeconds
        let cpu = store.cpuHistory.window(seconds: seconds)
        cpuHistory = cpu.values
        windowCapacity = cpu.capacity
        gpuHistory = store.gpuHistory.window(seconds: seconds).values
        memoryHistory = store.memoryHistory.window(seconds: seconds).values
        uploadHistory = store.uploadHistory.window(seconds: seconds).values
        downloadHistory = store.downloadHistory.window(seconds: seconds).values

        // Velocidad negociada del enlace Wi-Fi (Mbps). Ethernet: pendiente.
        if let rate = CWWiFiClient.shared().interface()?.transmitRate(), rate > 0 {
            linkSpeedText = rate >= 1000
                ? String(format: "%.1f Gbps", rate / 1000)
                : String(format: "%.0f Mbps", rate)
        }
    }
}
