# BtoStats — Requerimientos

**Versión**: 1.0 · **Estado**: vigente

## Visión

Reemplazar el conjunto de utilidades sueltas de barra de menús (monitores de CPU,
temperatura, ventiladores, disco, red, RAM, "liberadores" de memoria) con UNA sola app
nativa, sencilla y visualmente cuidada, con estadísticas del sistema en tiempo real.

## R1 — Widget en la barra de menús

- Icono/área en la barra de menús con una **cuadrícula compacta**: varias columnas ×
  varias filas de texto pequeño, actualizada en tiempo real (~1 s).
- Métricas candidatas por celda (cada una con **check para activar/desactivar**):
  - CPU % (total; opcional por clúster de núcleos)
  - GPU %
  - Temperatura (CPU/GPU/sensores)
  - Ventiladores (RPM)
  - RAM usada (% y/o GB)
  - Red: subida y bajada (B/s en vivo)
  - Disco: tamaño total y espacio disponible
  - Energía/consumo (W) — si es viable sin privilegios
- El usuario elige qué celdas se muestran y en qué orden (configurable, R6).

## R2 — Panel grande al hacer clic

- Clic en el widget → panel grande, más visual, con:
  - Gráficos en tiempo real (líneas/áreas por métrica, histórico corto).
  - KPIs grandes (números resumen).
  - **Top procesos por RAM** — qué consume memoria.
  - **Top procesos por CPU** — qué consume CPU.
  - **Top procesos por GPU / red / energía** — según viabilidad técnica.
  - Detalle de disco (volúmenes, usado/libre), red (interfaz, IP, velocidad),
    ventiladores y temperatura por sensor.

## R3 — Acciones

- **Diagnóstico de RAM** honesto: presión de memoria real y mayores consumidores
  (sin "liberadores" mágicos).
- **Matar procesos** desde los tops (con confirmación; primero terminación suave,
  luego forzada).
- Liberar CPU/GPU = identificar y terminar el proceso glotón.

## R4 — Tiempo real

- Refresh por defecto 1 s en el widget; el panel puede muestrear más fino.
- El propio monitoreo debe ser liviano (<1–2 % de CPU).

## R5 — Plataforma

- macOS 14+, Apple Silicon. App nativa Swift. Sin App Store, sin sudo.
- Hardware de referencia para pruebas: MacBook Pro M5 Pro, macOS 26.

## R6 — Configuración (todo parametrizable)

- Preferencias con checks por métrica, orden de celdas, cadencia de refresh,
  unidades, y arranque al iniciar sesión (launch at login).

## Fuera de alcance v1

- Notificaciones remotas, histórico persistente largo, soporte Intel.
