# BtoStats — Viabilidad técnica

Investigación técnica (julio 2026) contrastada con implementaciones open source
(exelban/stats master, licencia permisiva) y documentación de Apple. Todo lo marcado **[V]** fue
verificado empíricamente en el hardware de referencia (MacBook Pro M5 Pro / Mac17,9,
macOS 26.5.2, usuario normal, **sin sudo**) con binarios de prueba compilados.

**Veredicto global: todo el requerimiento es viable sin sudo.** Ninguna métrica ni
acción de las fases 1-5 necesita helper privilegiado.

## 1. Métricas núcleo — sí, APIs públicas [V]

| Métrica | API | Costo/llamada [V] | Cadencia |
|---|---|---|---|
| CPU % total | `host_statistics(HOST_CPU_LOAD_INFO)` | 0.5 µs | 1 s |
| CPU % por core | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | 4.5 µs | 1 s, solo con panel abierto |
| RAM + presión | `host_statistics64(HOST_VM_INFO64)` + `kern.memorystatus_vm_pressure_level` | 1.4 µs | 1–2 s |
| Red ↑↓ | `sysctl IFMIB_IFDATA` por interfaz → `ifmibdata.ifmd_data` (64-bit real) | ~25 µs | 1 s |
| Disco | `statfs` + `volumeAvailableCapacityForImportantUsage` | 0.5 µs | 30–60 s |

Costo total de sondeo ≈ 30 µs/s ≈ 0.003 % de un core. El consumo real lo dominará el
redibujado del status item — ahí hay que optimizar, no en los readers.

**Gotchas obligatorios** (todos con evidencia):
- `vm_deallocate` del array de `host_processor_info` en CADA ciclo o hay leak.
- Ticks UInt32 → deltas con `&-` (overflow-safe).
- Page size en Apple Silicon = **16384**: usar `vm_page_size`, jamás 4096.
- Red — hallazgo propio [V]: en macOS 26, `NET_RT_IFLIST2` entrega `ifi_ibytes/ifi_obytes`
  **truncados a 32 bits a binarios de terceros** (coinciden con netstat módulo 2³²; los
  binarios de Apple y el intérprete de Swift sí reciben 64 bits). NO usarlo. Tampoco
  `getifaddrs`/`if_data` (32-bit por diseño). **Fuente correcta: sysctl
  `{CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL}`** →
  `ifmibdata.ifmd_data` (if_data64 real; verificado idéntico byte a byte a netstat).
  Filtrar `lo0`, `utun*` (VPN dobla tráfico), `awdl0`, `llw0`, `gif/stf/bridge/ap`.
  Interfaz primaria: `SCDynamicStore "State:/Network/Global/IPv4"`.
- Descartar la primera muestra de cada delta (CPU y red).
- Topología [V]: `hw.nperflevels=2`; en M5 Pro perflevel0=**"Super"** (6 cores),
  perflevel1="Performance" (12). En M5 NO existen nombres "Efficiency/E-cores" —
  leer nombres y conteos en runtime, nunca asumirlos.
- Disco: mostrar "disponible" (estilo Finder, incluye purgeable) y "libre real" (statfs)
  como dos números — evita el clásico "no coincide con Finder".
- Fórmula de RAM usada no documentada por Apple; la de stats:
  `active+inactive+speculative+wired+compressed−purgeable−external`. La alternativa
  (`internal−purgeable+wired+compressed`) también aproxima Activity Monitor;
  ±100-300 MB de diferencia es normal.

## 2. Temperatura y ventiladores — sí, SMC lectura sin sudo [V]

- **AppleSMC IOKit clásico funciona en M5 Pro sin privilegios** [V]: matching `"AppleSMC"`
  → clase `AppleSMCKeysEndpoint`, `IOServiceOpen` OK, lectura con selector 2.
  En el equipo de referencia: **3485 claves**, 256 de temperatura tipo `flt `,
  **18 claves `Tp0*`** (CPU: Tp00–Tp0K = 6 cores Super, Tp0O–Tp0y = 12 Performance),
  **42 claves `Tg*`** (GPU), `FNum=2` ventiladores, RPM en `F0Ac`/`F1Ac` (~2317/2502
  en reposo [V]), rangos `F0Mn/F0Mx` = 2317/7826.
- Cliente propio ~200 líneas portando `SMC/smc.swift` de stats **sin los métodos write**.
- **Filtrar la tabla de claves contra las que existen de verdad** en el equipo
  (ejemplo real: `Tg1g` figura en la tabla M5 de stats pero NO existe en Mac17,9);
  las claves cambian por generación e incluso por dispositivo con el mismo SoC.
  Fallback: enumeración dinámica `#KEY` → índice.
- Sensores HID (`IOHIDEventSystemClient`, privada): degradada en M5 — solo `PMU tdie1-14`
  útiles; `PMU tdev*` devuelven basura (≈ −9200) [V] → filtrar por rango físico. Fuente
  secundaria nada más.
- `ProcessInfo.thermalState`: única API 100 % pública — usar para badge de presión térmica.
- **NO viable / descartado**: `powermetrics` (exige sudo [V]), control de ventiladores
  (escritura SMC = root + riesgo térmico), App Sandbox (bloquea IOServiceOpen — no sandboxear).

## 3. GPU % — sí, IOKit público [V]

- `IOServiceMatching("IOAccelerator")` + `IORegistryEntryCreateCFProperties` →
  `PerformanceStatistics["Device Utilization %"]` [V]: en el equipo de referencia el
  servicio es `AGXAcceleratorG17X` (Apple M5 Pro, 20 cores) y se leyó utilización en
  vivo sin sudo.
- No existe API pública para GPU % global — Activity Monitor usa lo mismo. Las FUNCIONES
  son IOKit público; lo no documentado son las claves del diccionario (estables ~10 años).
- Actualiza sub-segundo y puede dar 0 transitorio bajo carga [V] → suavizar con EMA;
  `Renderer/Tiler` pueden superar 100 → clamp.
- Cachear el `io_service_t` y releer solo propiedades por tick.
- Fase posterior opcional: `libIOReport` (privada, sin sudo [V]) para watts de GPU
  ("Energy Model" / "GPU Energy") y residencia de P-states (canal `GPUPH` [V]).
  Enumerar canales en runtime, fail-soft si no existen. Sin temperatura ni clock aquí —
  eso sale del SMC (§2).

## 4. Top procesos y acciones — sí, con matices [V]

- **Top CPU**: spawn `/bin/ps -Aceo pid,pcpu,comm -r` (~30 ms [V]) — ve TODOS los procesos
  (root incluido) porque `ps` lleva la entitlement `com.apple.system-task-ports.read` en
  su propia firma. Mismo método que stats.
- **Top RAM**: spawn `/usr/bin/top -l 1 -o mem` — cuesta **~750 ms** de CPU [V] →
  cadencia 5 s, cola propia, jamás atado al tick de 1 s.
- **Top red por proceso**: `nettop -P -x -L 1 -n ...` — **`-n` es OBLIGATORIO**: sin él
  cada muestra bloquea ~5 s por resolución DNS inversa; con `-n` son ~17 ms [V].
  Fase posterior: `NetworkStatistics.framework` privado vía dlopen (funciona sin sudo [V];
  ojo: rxBytes llega en 0 en la primera descripción de forma sistémica [V] → polling de
  descripciones imprescindible, con fallback a nettop).
- `proc_pid_rusage` da `ri_phys_footprint` exacto pero SOLO del uid propio (EPERM para
  root/otros [V]) — solo para enriquecer, no para el top global.
- **Matar procesos**: apps GUI → `NSRunningApplication.terminate()` (respeta "¿guardar?")
  → `forceTerminate()`; resto del uid propio → `kill` SIGTERM → espera 3-5 s → SIGKILL.
  Procesos de otro uid: botón deshabilitado con tooltip (cubre el 99 % real: apps colgadas
  y Electron corren con el uid del usuario). One-shot con contraseña vía osascript solo
  bajo demanda explícita.
- **"Liberar RAM" — honestidad**: `purge` exige sudo [V] y NO libera memoria de apps (solo
  caché de disco); el truco de las apps "Memory Clean" (alocar hasta forzar compresión) es
  cosmético y puede EMPEORAR el rendimiento. Decisión de diseño: mostrar presión de
  memoria real + top consumidores + terminar procesos glotones; botón "presión
  experimental" claramente etiquetado, OFF por defecto. `memory_pressure -S` sin sudo
  falla pero con exit code 0 [V] — parsear stderr si se usa.

## 5. UI — NSStatusItem clásico, panel NSPanel

- **NO MenuBarExtra** (SwiftUI): sin vista custom en el label ni control de fuente — la
  cuadrícula de 2 filas a 9 pt es imposible sin hacks. NSStatusItem con vista propia
  (patrón stats y eul).
- Primera etapa: `NSHostingView` en el button (rápido de construir). Meta: `NSView` con
  `draw(_:)` puro estilo `StackWidget` de stats (cero re-layout SwiftUI a 1 Hz):
  rowHeight = frame.height/2, margin.y=2, spacing=2.
- Fuente: `monospacedDigitSystemFont(ofSize: 9)` — dígitos tabulares (sin jitter de
  ancho, sin verse "de terminal"). stats usa 9-10 pt en sus widgets de 2 filas.
  Actualizar `item.length` SOLO cuando cambia el ancho (evita "baile").
- **Panel grande: NSPanel** `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` + level
  `.floating`, cierre en `windowDidResignKey` con opción "pin" — NO NSPopover (dismiss
  agresivo, falla en fullscreen, no se puede dejar abierto mirando gráficos). Dentro del
  panel SÍ SwiftUI + Swift Charts. No mutar styleMask en runtime (rompe key-window).
- **macOS 26 — permiso nuevo**: System Settings → **Menu Bar**; si la app no está
  autorizada, el ítem NO aparece aunque corra (issue #2182 de stats). Detectar y guiar
  al usuario en el primer arranque.
- Launch at login: `SMAppService.mainApp.register()` + manejo `.requiresApproval` →
  `openSystemSettingsLoginItems()`. El status puede volver `.notFound` al desactivarlo;
  evitar copias duplicadas de la .app.
- El ORDEN de los status items lo decide macOS, no la app.

## 6. Referencia principal: exelban/stats

- **licencia permisiva** (LICENSE verificada) — código y enfoques aprovechables conservando el aviso de
  copyright (sección "Acknowledgements"). v3.0.9 (jul-2026), mantenimiento activo,
  **ya soporta M5 y macOS 26**. El propio mantenedor admite que identificar sensores
  entre generaciones de SoC es "basically guesswork" (issue #3399) → refuerza la
  política fail-soft.
- Patrón por módulo a replicar: `main` (Module) + `readers` + `widget` + `popup` +
  `settings`. Su único componente root es el helper de control de ventiladores — no se
  necesita aquí.
- **iGlance: GPL-3.0 y abandonado — no copiar código** (contaminaría la licencia).
  eul: licencia permisiva pero inactivo desde 2024 (pre-M5) — solo inspiración de UI.
