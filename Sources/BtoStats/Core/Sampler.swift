import Foundation

/// Dos relojes de muestreo en una cola .utility:
/// rápido (cuadrícula, ~1 s) y lento (disco y futuros tops, ~60 s).
/// Los handlers corren EN la cola del sampler; publicar a main es
/// responsabilidad del llamador.
final class Sampler {
    private let queue = DispatchQueue(label: "btostats.sampler", qos: .utility)
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?

    func start(fastInterval: TimeInterval,
               slowInterval: TimeInterval,
               fast: @escaping () -> Void,
               slow: @escaping () -> Void) {
        stop()

        let ft = DispatchSource.makeTimerSource(queue: queue)
        ft.schedule(deadline: .now() + 0.1,
                    repeating: fastInterval,
                    leeway: .milliseconds(200))
        ft.setEventHandler(handler: fast)
        ft.resume()
        fastTimer = ft

        let st = DispatchSource.makeTimerSource(queue: queue)
        st.schedule(deadline: .now() + 0.3,
                    repeating: slowInterval,
                    leeway: .seconds(5))
        st.setEventHandler(handler: slow)
        st.resume()
        slowTimer = st
    }

    func stop() {
        fastTimer?.cancel()
        slowTimer?.cancel()
        fastTimer = nil
        slowTimer = nil
    }
}
