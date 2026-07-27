import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricStore()
    private let sampler = Sampler()
    private var statusController: StatusItemController?

    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let diskReader = DiskReader()
    private let gpuReader = GPUReader()
    private let sensorsReader = SensorsReader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)
        NotificationCenter.default.addObserver(forName: AppConfig.changedNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.startSampling()
            self?.statusController?.render()
        }
        startSampling()
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
                let gpu = self.gpuReader.read()
                let sensors = self.sensorsReader.read()
                DispatchQueue.main.async {
                    self.store.updateFast(cpu: cpu, memory: memory, network: network,
                                          gpu: gpu, sensors: sensors)
                    self.statusController?.render()
                }
            },
            slow: { [weak self] in
                guard let self else { return }
                let disk = self.diskReader.read()
                DispatchQueue.main.async {
                    self.store.updateDisk(disk)
                    self.statusController?.render()
                }
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.stop()
    }
}
