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

## Fase 3 — Configuración (todo parametrizable) ✅

- [x] Preferencias (ventana SwiftUI): check por métrica individual, orden por
      arrastre, cadencia 1-5 s. Cambios aplican en vivo.
- [x] Persistencia en UserDefaults (suite ec.bto.BtoStats); los cambios externos
      con `defaults write` también se reflejan en vivo (checks/orden).
- [x] Launch at login (SMAppService) — toggle listo; activo cuando la app esté
      empaquetada como .app (fase 6). Deshabilitado con nota mientras tanto.

## Fase 4 — Panel grande ✅

- [x] Clic izquierdo → NSPanel flotante nonactivating (menú de detalle pasa a clic
      derecho). Cierra al perder foco; `pinned` para anclarlo (modo prueba).
- [x] SwiftUI + Swift Charts: 6 KPIs y 2 gráficos en vivo (CPU·GPU·RAM %, red ↑↓)
      sobre el histórico de 5 min del MetricStore.
- [x] Top procesos por CPU (`ps`), RAM (`top`, 5 s solo con panel abierto) y red
      (`nettop -n`, B/s por deltas; deltas negativos por sockets cerrados se
      descartan; hijos propios excluidos por ppid).
- [x] Modo `--top` para verificación por terminal.

## Fase 5 — Acciones ✅

- [x] Matar procesos desde los tops: botón ✕ con confirmación (Terminar educado /
      Forzar cierre / Cancelar); GUI vía NSRunningApplication, resto TERM→KILL.
      Procesos de otro usuario: deshabilitado con explicación (helper fase 8).
      Verificado end-to-end por CLI (--kill): propio muere, root bloqueado.
- [x] Salud de RAM honesta: presión real del kernel (verde/amarillo/rojo) con
      consejo claro; sin "liberadores" mágicos (purge es teatro — VIABILIDAD §4).

## Fase 6 — Pulido / empaquetado ✅ (instalación pospuesta)

- [x] Icono profesional (assets/icon-1024.png → BtoStats.icns).
- [x] Empaquetado: scripts/package.sh → dist/BtoStats.app firmada ad hoc + zip
      (LSUIElement, bundle id ec.bto.BtoStats). Verificado ejecutando el bundle.
- [x] README completo + LICENSE licencia permisiva + release v0.6.0 en GitHub.
- [x] Gates pre-release: code review + security review con verificación
      adversarial; corregidos: wraparound de red al desaparecer interfaces,
      carrera pid-reuse en matar procesos (verificación de identidad),
      deadlock por stderr sin drenar + watchdog en spawns, baseline de red
      del panel, top red congelado, NaN en EMA de GPU, parseMemory sin trap.
- [ ] Instalación en /Applications: pospuesta a fase 8/9 a pedido (se sigue
      compilando en modo dev para no duplicar instancias).
- [ ] Mini-gráficos (sparklines) opcionales en el status item (backlog).
- [x] Deuda del review (menores): cache de KeyInfo SMC, mach_port_deallocate,
      una sola copia del IORegistry por tick, sanear nombre en el diálogo,
      estado "no disponible" en menú, parser nettop con comas.
- [x] Manual con capturas (docs/MANUAL.md).

## Fase 7 — Widget de escritorio ✅

- [x] Ventana propia a nivel escritorio (desktop+1: sobre el fondo, bajo las
      ventanas; todos los espacios) — WidgetKit descartado (no da 1 Hz).
- [x] Anillos en tiempo real: S (CPU), M (CPU/GPU/RAM/Disk 2×2), L (+Temp y
      red ↑↓ + disco libre), XL (+mini gráfico de histórico CPU/RAM).
- [x] OFF por defecto; toggle y tamaño en Preferencias (cambios en vivo);
      arrastrable con posición persistente.
- [x] Métricas de los anillos configurables (respetan checks y orden de
      Preferencias; XL con sparkline de 5 líneas). Panel anclable (opción).

## Fase 8 — Helper de administrador ✅ (opcional, OFF por defecto)

Instalable desde Preferencias con aprobación única (SMAppService.daemon +
NSXPC; validación del cliente por ruta del ejecutable; superficie de 3
operaciones cerradas, jamás un shell privilegiado — ver VIABILIDAD §4).

- [x] Top GPU exacto por proceso (powermetrics --show-process-gpu vía helper;
      el panel muestra ms/s cuando el helper está activo, aprox. si no).
- [x] Matar procesos de otros usuarios/root (doble confirmación + verificación
      de identidad del pid en el helper; nunca pid<=1).
- [x] purgeDiskCache (experimental, etiquetado; purge no libera memoria de apps).
- [x] Instancia única (evita íconos duplicados dev vs .app).
- [x] Empaquetado con helper embebido + LaunchDaemon plist; firma en orden.

## Fase 9 — Release final e instalación ✅

- [x] Review de seguridad del helper (gate superado; correcciones en VIABILIDAD §7).
- [x] Instalar BtoStats.app en /Applications; instancia única verificada.
- [x] Release v1.0.0.

## Backlog (post-1.0, cuando pique el gusanillo)

- Widget para la galería nativa "Editar widgets" (WidgetKit, versión lenta).
- Consumo de energía en watts (vía helper / IOReport).
- Histórico de día/mes en gráficas (persistencia a disco).
- Ancho de banda del enlace Ethernet (hoy solo Wi-Fi).
- Sparklines opcionales en el status item.
