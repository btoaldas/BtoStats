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
    private var clickOutsideMonitor: Any?

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
            newPanel.styleMask = [.titled, .closable, .nonactivatingPanel]
            newPanel.title = "BtoStats — monitor en vivo"
            newPanel.titleVisibility = .visible
            newPanel.isMovableByWindowBackground = true
            newPanel.level = .floating
            newPanel.becomesKeyOnlyIfNeeded = false
            newPanel.isReleasedWhenClosed = false
            // canJoinAllSpaces (no moveToActiveSpace): tras un orderOut,
            // moveToActiveSpace deja la ventana asignada a un Space viejo y el
            // WindowServer no la re-muestra (AppKit cree que está visible) —
            // el bug de "el clic no hace nada hasta abrir Preferencias".
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.delegate = self
            panel = newPanel
        }
        model.refresh(from: store)
        // medir ANTES de posicionar: en la primera apertura SwiftUI aún no
        // calculó el tamaño real y el panel se clampeaba con un frame viejo
        // (crecía luego hacia la derecha y se cortaba contra el borde)
        if let contentView = panel?.contentViewController?.view {
            contentView.layoutSubtreeIfNeeded()
            panel?.setContentSize(contentView.fittingSize)
        }
        position(relativeTo: button)
        // El combo completo es el ÚNICO que muestra el panel de forma fiable
        // en macOS 26 (multi-pantalla/Spaces): activar la app + hacer key +
        // forzar el orden. orderFrontRegardless solo NO basta, y sin activar
        // la app makeKeyAndOrderFront tampoco (verificado empíricamente).
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        // segunda pasada al siguiente ciclo: si el layout ajustó el tamaño
        // tras mostrarse, re-clampear a la pantalla
        DispatchQueue.main.async { [weak self] in self?.position(relativeTo: button) }
        startClickOutsideMonitor()
        startProcessSampling()
    }

    func close() {
        stopProcessSampling()
        stopClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    /// Clic en cualquier OTRA app (fuera del panel) → cerrar. Los clics dentro
    /// del panel o en nuestro status item son de nuestra app y no pasan por
    /// este monitor, así que no hay carreras.
    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.pinned, !AppConfig.shared.panelPinned,
                  let frame = self.panel?.frame else { return }
            if !frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.close() }
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func position(relativeTo button: NSStatusBarButton?) {
        guard let panel else { return }
        guard let buttonWindow = button?.window, let screen = buttonWindow.screen else {
            panel.center()
            return
        }
        let buttonFrame = buttonWindow.frame
        let size = panel.frame.size
        let visible = screen.visibleFrame
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = buttonFrame.minY - size.height - 6
        y = max(y, visible.minY + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Top procesos (5 s, solo panel visible)

    private func startProcessSampling() {
        processQueue.async { [weak self] in self?.processReader.resetNetworkBaseline() }
        sampleProcesses() // baseline de red (aún sin deltas)
        // segunda muestra a 1.5 s: el top de red necesita 2 muestras para el
        // delta; sin esto quedaría "midiendo…" hasta el primer tick de 5 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.isVisible else { return }
            self.sampleProcesses()
        }
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
                self.model.topNetwork = snapshot.topNetwork
            }
        }
        // Nota: NO hay top GPU exacto por proceso en Apple Silicon —
        // powermetrics no expone GPU/proceso en M-series (verificado en M5),
        // ni con root. Se usa siempre el aproximado por muestreo.
        model.helperActive = HelperClient.shared.isInstalled
    }

}
