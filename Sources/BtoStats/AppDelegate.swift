import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricStore()
    private let sampler = Sampler()
    private var statusController: StatusItemController?
    private let desktopWidget = DesktopWidgetController()

    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let diskReader = DiskReader()
    private let gpuReader = GPUReader()
    private let sensorsReader = SensorsReader()
    private let systemReader = SystemReader()
    private let wifiReader = WiFiReader()
    private let batteryReader = BatteryReader()
    private let diskIOReader = DiskIOReader()
    private let bluetoothReader = BluetoothReader()
    private let powerReader = PowerReader()
    private var lastPower: PowerReader.Snapshot?
    private var lastSystem: SystemReader.Snapshot?
    private var lastWiFi: WiFiReader.Snapshot?
    private var lastBattery: BatteryReader.Snapshot?
    private var tickCounter = 0
    private var lastGPU: GPUReader.Snapshot?
    private var lastSensors: SensorsReader.Snapshot?
    private let alertMonitor = AlertMonitor()
    private var uptimeAtLaunch = ProcessInfo.processInfo.systemUptime

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)
        NotificationCenter.default.addObserver(forName: AppConfig.changedNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.startSampling()
            self?.statusController?.render()
        }
        startSampling()
        alertMonitor.requestAuthorizationIfNeeded()

        // Modo de prueba: abre Preferencias a los 2 s (capturas del manual).
        if ProcessInfo.processInfo.environment["BTOSTATS_TEST_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.activate(ignoringOtherApps: true)
                SettingsWindowController().show()
            }
        }

        // Modo de prueba: abre el panel anclado a los 2 s (verificación sin UI manual).
        if ProcessInfo.processInfo.environment["BTOSTATS_TEST_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let controller = self.statusController else { return }
                controller.panelController.pinned = true
                controller.panelController.toggle(relativeTo: nil, store: self.store)
            }
        }
    }

    private func startSampling() {
        sampler.start(
            fastInterval: AppConfig.shared.fastInterval,
            slowInterval: 60.0,
            fast: { [weak self] in
                guard let self else { return }
                let cpu = self.cpuReader.read()
                let memory = self.memoryReader.read()
                let network = self.networkReader.read()
                let diskIO = self.diskIOReader.read()
                // GPU (copia del IORegistry) y sensores (~60 lecturas SMC) son
                // los readers caros: se leen cada 2 ticks. Temp/GPU no cambian
                // de forma perceptible en 1 s; baja el consumo base a la mitad.
                self.tickCounter += 1
                if self.tickCounter % 2 == 0 {
                    self.lastGPU = self.gpuReader.read()
                    self.lastSensors = self.sensorsReader.read()
                    self.lastSystem = self.systemReader.read()
                    self.lastWiFi = self.wifiReader.read()
                    self.lastBattery = self.batteryReader.read()
                    self.lastPower = self.powerReader.read()
                }
                let gpu = self.lastGPU
                let sensors = self.lastSensors
                let system = self.lastSystem
                DispatchQueue.main.async {
                    self.store.updateFast(cpu: cpu, memory: memory, network: network,
                                          gpu: gpu, sensors: sensors)
                    self.store.updateSystem(system)
                    self.store.updateWiFi(self.lastWiFi)
                    self.store.updateBattery(self.lastBattery)
                    self.store.updateDiskIO(diskIO)
                    self.store.updatePower(self.lastPower)
                    self.statusController?.render()
                    self.statusController?.panelController.refresh(from: self.store)
                    // sync (no solo refresh): permite activar/desactivar/redimensionar
                    // en vivo, incluso con `defaults write` externo
                    self.desktopWidget.sync(store: self.store)
                    self.alertMonitor.check(store: self.store,
                                            now: ProcessInfo.processInfo.systemUptime)
                }
            },
            slow: { [weak self] in
                guard let self else { return }
                let disk = self.diskReader.read()
                let bt = self.bluetoothReader.read()
                DispatchQueue.main.async {
                    self.store.updateDisk(disk)
                    self.store.updateBluetooth(bt)
                    self.statusController?.render()
                }
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.stop()
    }
}
