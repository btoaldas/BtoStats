# BtoStats — Arquitectura

Patrón inspirado en exelban/stats (proyecto de terceros bajo licencia licencia permisiva — la
licencia de BtoStats es PolyForm Strict, ver LICENSE): cada métrica es un módulo con
**Reader** (datos) desacoplado de **Widget** (celda en el status item) y **Popup**
(sección del panel grande). Basado en docs/VIABILIDAD.md.

## Capas

```
┌────────────────────────────────────────────────────────┐
│ UI                                                     │
│  StatusItemController — NSStatusItem + vista cuadrícula│
│  PanelController — NSPanel flotante + SwiftUI/Charts   │
│  SettingsWindow — checks, orden, cadencias             │
├────────────────────────────────────────────────────────┤
│ Core                                                   │
│  Sampler — DispatchSourceTimer 1 Hz (leeway 200 ms,    │
│            cola .utility); segundo timer lento (5-60 s)│
│  MetricStore — último snapshot + ring buffer por       │
│            métrica (histórico corto para gráficos)     │
│  AppConfig — UserDefaults; TODO parametrizable         │
├────────────────────────────────────────────────────────┤
│ Readers (sin UI, un archivo por métrica)               │
│  CPUReader        host_statistics / host_processor_info│
│  MemoryReader     host_statistics64 + presión          │
│  NetworkReader    sysctl NET_RT_IFLIST2 (64-bit)       │
│  DiskReader       statfs + importantUsage (60 s)       │
│  GPUReader        IOAccelerator PerformanceStatistics  │
│  SensorsReader    SMC read-only (temp + fans)          │
│  ProcessReader    ps (CPU) / top (RAM, 5 s) / nettop -n│
├────────────────────────────────────────────────────────┤
│ Acciones                                               │
│  ProcessKiller    terminate→forceTerminate / TERM→KILL │
│                   (siempre con confirmación en UI)     │
│  MemoryAdvisor    presión real + top consumidores      │
│                   (nada de "purge mágico")             │
└────────────────────────────────────────────────────────┘
```

## Reglas de diseño

1. **Readers puros**: `read() -> Snapshot?`, sin AppKit, testeables. Deltas internos
   (primera muestra se descarta). Cada reader declara su cadencia por defecto y
   respeta la configurada.
2. **Dos relojes**: tick rápido (1 s, configurable 1-5 s) para cuadrícula; tick lento
   (5-60 s) para disco y top procesos (top cuesta ~750 ms — jamás en el tick rápido).
   `host_processor_info` (por core) solo corre con el panel abierto.
3. **Fail-soft en todo lo no documentado**: SMC/GPU/IOReport — si una clave o canal no
   existe en el chip, la métrica se oculta sola, sin crash y sin log ruidoso. Tablas de
   claves SMC filtradas contra las claves reales del equipo al arrancar.
4. **UI a 1 Hz barata**: fase 1 NSHostingView; fase 2 NSView.draw() puro estilo
   StackWidget. monospacedDigitSystemFont 9 pt; item.length solo cambia si cambia el ancho.
5. **Config primero**: cada celda de la cuadrícula = check; orden arrastrable;
   cadencia global y por reader; unidades. Sin feature hardcodeada.
6. **Sin sandbox** (bloquea SMC), sin App Store, distribución local firmada ad hoc.
   Sin helper root en fases 1-5.
7. **Confirmación siempre** antes de matar un proceso; procesos de otro uid → botón
   deshabilitado con tooltip.

## Flujo del tick rápido

```
Sampler(1 Hz) → CPUReader.read() ┐
                MemoryReader     ├→ MetricStore.push(snapshots)
                NetworkReader    ┘        │
                GPUReader                 ├→ StatusItemController.render(grid)
                SensorsReader             └→ PanelController.render() (si abierto)
```

## Estructura de archivos (meta)

```
Sources/BtoStats/
  main.swift, AppDelegate.swift
  Core/     Sampler.swift, MetricStore.swift, AppConfig.swift
  Readers/  CPUReader.swift, MemoryReader.swift, NetworkReader.swift,
            DiskReader.swift, GPUReader.swift, SensorsReader.swift,
            SMC.swift, ProcessReader.swift
  UI/       StatusItemController.swift, GridView.swift,
            PanelController.swift, Panel/*.swift (SwiftUI),
            SettingsWindow.swift
  Actions/  ProcessKiller.swift, MemoryAdvisor.swift
```

## Deudas conocidas

- Fórmula RAM propia vs. la de stats: comparar ambas contra Activity Monitor y elegir
  (documentado en VIABILIDAD §1).
- Falta manejo del permiso "Menu Bar" de macOS 26 en el primer arranque.
- Columna de disco: alinear el valor de la fila inferior cuando no hay label.
