import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricStore()
    private let sampler = Sampler()
    private var statusController: StatusItemController?

    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let diskReader = DiskReader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)

        sampler.start(
            fastInterval: 1.0,
            slowInterval: 60.0,
            fast: { [weak self] in
                guard let self else { return }
                let cpu = self.cpuReader.read()
                let memory = self.memoryReader.read()
                let network = self.networkReader.read()
                DispatchQueue.main.async {
                    self.store.updateFast(cpu: cpu, memory: memory, network: network)
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
