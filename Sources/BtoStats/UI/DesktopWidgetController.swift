import AppKit
import SwiftUI

/// Ventana-widget pegada al escritorio: sobre el fondo de pantalla y debajo de
/// las ventanas normales, visible en todos los espacios, arrastrable, con
/// posición persistente. (WidgetKit no permite refresh de ~1 s — por eso es
/// una ventana propia; ver docs/REQUERIMIENTOS.md R7.)
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let model = DesktopWidgetModel()
    private var window: NSWindow?
    private var currentSize: AppConfig.DesktopWidgetSize?

    var isActive: Bool { window != nil }

    /// Sincroniza con la configuración: crea, destruye o redimensiona.
    func sync(store: MetricStore) {
        let config = AppConfig.shared
        guard config.desktopWidgetEnabled else {
            if window != nil { hide() }
            return
        }
        if window == nil || currentSize != config.desktopWidgetSize {
            show(size: config.desktopWidgetSize)
        }
        model.refresh(from: store)
    }

    private func show(size: AppConfig.DesktopWidgetSize) {
        hide()
        let hosting = NSHostingController(rootView: DesktopWidgetView(model: model, size: size))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.styleMask = [.borderless]
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = true
        newWindow.isMovableByWindowBackground = true
        newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.setContentSize(hosting.view.fittingSize)

        if let origin = AppConfig.shared.desktopWidgetOrigin {
            newWindow.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            newWindow.setFrameOrigin(NSPoint(x: frame.maxX - newWindow.frame.width - 24,
                                             y: frame.maxY - newWindow.frame.height - 24))
        }
        newWindow.orderFront(nil)
        window = newWindow
        currentSize = size
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        currentSize = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        AppConfig.shared.desktopWidgetOrigin = CGPoint(x: window.frame.origin.x,
                                                       y: window.frame.origin.y)
    }
}
