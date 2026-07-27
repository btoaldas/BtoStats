# BtoStats — Roadmap

Fases chicas; cada una termina compilada, instalada y probada con evidencia
reproducible antes de darse por cerrada.

## Fase 0 — Esqueleto ✅

- [x] Proyecto SPM, status item con cuadrícula 2 filas (fuente mono 9 pt).
- [x] CPU % real (host_processor_info) y RAM % real (host_statistics64).
- [x] Menú con detalle y salida. Lecturas contrastadas contra iStat Menus (coinciden).

## Fase 1 — Métricas núcleo completas ✅

- [x] Red ↑↓ B/s (sysctl IFMIB_IFDATA, 64-bit; NET_RT_IFLIST2 descartado por
      truncamiento a 32 bits en macOS 26 — ver VIABILIDAD §1).
- [x] Disco: total / libre real / disponible estilo Finder (verificado contra df).
- [x] Histórico corto en memoria (RingBuffer, 300 muestras) para gráficos.
- [x] Refactor a Sampler (2 relojes) / MetricStore / StatusItemController.
- [x] Modo `--sample` para verificación numérica por terminal.

## Fase 2 — Sensores y GPU ✅

- [x] GPU % (IOKit IOAccelerator PerformanceStatistics, EMA + clamp; verificado
      contra ioreg) y memoria GPU en uso (menú).
- [x] Cliente SMC read-only propio (enumeración dinámica de claves, filtro por
      rango físico). Temperatura CPU/GPU en cuadrícula y menú; ventiladores RPM
      en menú. Verificado con prueba térmica (carga → +10 °C → enfriamiento).

## Fase 3 — Configuración (todo parametrizable)

- [ ] Preferencias: checks por métrica, orden de celdas, cadencia, unidades.
- [ ] Persistencia en UserDefaults. Launch at login (SMAppService).

## Fase 4 — Panel grande

- [ ] Clic → NSPanel flotante (no popover) con SwiftUI + Swift Charts, gráficos en vivo y KPIs.
- [ ] Top procesos por CPU (`ps`, ~30 ms) y RAM (`top`, ~750 ms → cadencia 5 s).
- [ ] Top procesos por red (`nettop -n` obligatorio; luego NetworkStatistics.framework).

## Fase 5 — Acciones

- [ ] Matar procesos con confirmación (terminate → forceTerminate / TERM → KILL);
      otros uid deshabilitado con tooltip.
- [ ] "Salud de RAM" honesta: presión real + top consumidores (purge es teatro — ver
      VIABILIDAD §4); botón experimental OFF por defecto.

## Fase 6 — Pulido

- [ ] Icono, empaquetado .app, instalación en /Applications.
- [ ] Mini-gráficos (sparklines) opcionales en el status item.
- [ ] Manual con capturas.
