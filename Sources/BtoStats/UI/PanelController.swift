import AppKit
import SwiftUI

/// Panel flotante bajo el status item (NSPanel nonactivating — se puede mirar
/// sin robar el foco de la app activa; se cierra al hacer clic fuera).
/// Los top procesos se muestrean SOLO mientras el panel está visible (top
/// cuesta ~750 ms — docs/VIABILIDAD.md §4).
final class PanelController: NSObject, NSWindowDelegate {
    let model = PanelModel()
    private var panel: NSPanel?
    private let processReader = ProcessReader()
    private var processTimer: Timer?
    private let processQueue = DispatchQueue(label: "btostats.processes", qos: .utility)

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Con pin activo el panel no se cierra al perder el foco (usado por el
    /// modo de prueba BTOSTATS_TEST_PANEL; luego será el botón de anclar).
    var pinned = false

    func toggle(relativeTo button: NSStatusBarButton?, store: MetricStore) {
        if isVisible {
            close()
        } else {
            show(relativeTo: button, store: store)
        }
    }

    func refresh(from store: MetricStore) {
        guard isVisible else { return }
        model.refresh(from: store)
    }

    private func show(relativeTo button: NSStatusBarButton?, store: MetricStore) {
        if panel == nil {
            let hosting = NSHostingController(rootView: PanelView(model: model))
            let newPanel = NSPanel(contentViewController: hosting)
            newPanel.styleMask = [.titled, .nonactivatingPanel, .fullSizeContentView]
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.isMovableByWindowBackground = true
            newPanel.level = .floating
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.isReleasedWhenClosed = false
            newPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            newPanel.delegate = self
            panel = newPanel
        }
        model.refresh(from: store)
        position(relativeTo: button)
        panel?.makeKeyAndOrderFront(nil)
        startProcessSampling()
    }

    func close() {
        stopProcessSampling()
        panel?.orderOut(nil)
    }

    private func position(relativeTo button: NSStatusBarButton?) {
        guard let panel else { return }
        guard let buttonWindow = button?.window, let screen = buttonWindow.screen else {
            panel.center()
            return
        }
        let buttonFrame = buttonWindow.frame
        let size = panel.frame.size
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8),
                screen.visibleFrame.maxX - size.width - 8)
        let y = buttonFrame.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Top procesos (5 s, solo panel visible)

    private func startProcessSampling() {
        sampleProcesses() // primera muestra inmediata (baseline de red)
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sampleProcesses()
        }
        RunLoop.main.add(timer, forMode: .common)
        processTimer = timer
    }

    private func stopProcessSampling() {
        processTimer?.invalidate()
        processTimer = nil
    }

    private func sampleProcesses() {
        processQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.processReader.read()
            DispatchQueue.main.async {
                self.model.topCPU = snapshot.topCPU
                self.model.totalCPUPercent = snapshot.totalCPUPercent
                self.model.topRAM = snapshot.topRAM
                if !snapshot.topNetwork.isEmpty {
                    self.model.topNetwork = snapshot.topNetwork
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if !pinned { close() }
    }
}
