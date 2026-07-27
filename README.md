# BtoStats

<img src="assets/icon-1024.png" width="128" align="right" alt="Icono de BtoStats">

Monitor de sistema nativo para la barra de menús de macOS (Apple Silicon).
Una sola app liviana que reemplaza los monitores sueltos de CPU, GPU,
temperatura, ventiladores, RAM, red y disco — sin sudo, sin extensiones de
kernel y sin "liberadores de RAM" mágicos.

## Características

**Widget en la barra de menús** — cuadrícula compacta en tiempo real (~1 s):

- CPU %, RAM %, GPU %, temperatura de CPU, red ↑↓ (bloque indivisible: subida
  arriba, bajada abajo), disco libre (L) y total (T).
- Cada métrica se activa/desactiva y se reordena a gusto; 2, 3 o 4 filas con
  fuente escalonada; columnas alineadas por relleno monoespaciado exacto que
  se adapta dinámicamente al ancho de los valores.

**Panel** (clic izquierdo) — más visual, con zoom −/+ persistente:

- 6 KPIs grandes: CPU, GPU (+temp), RAM, temperatura (+ventiladores RPM),
  red y disco.
- Gráficos en vivo de 5 minutos (Swift Charts) con leyenda de colores:
  CPU/GPU/RAM y red ↑↓.
- Top procesos por CPU (doble lectura: % del equipo · % del uso actual),
  por RAM (uso · % del total), por red (B/s) y top GPU aproximado por
  muestreo del último proceso que envía trabajo al driver.
- Cerrar procesos con confirmación (terminar educado / forzar); los procesos
  de otros usuarios quedan bloqueados (sin privilegios).
- Salud de RAM honesta: presión real del kernel con semáforo y consejo claro.

**Menú de detalle** (clic derecho) — resumen textual + Preferencias.

## Técnica (sin sudo, verificado empíricamente)

| Métrica | Fuente |
|---|---|
| CPU | `host_statistics` / `host_processor_info` |
| RAM + presión | `host_statistics64` + `kern.memorystatus_vm_pressure_level` |
| Red | sysctl `IFMIB_IFDATA` (contadores de 64 bits reales) |
| Disco | `statfs` + capacidad "importante" estilo Finder |
| GPU | IOKit `IOAccelerator` → `PerformanceStatistics` |
| Temperatura/ventiladores | Cliente SMC propio de solo lectura (claves descubiertas dinámicamente) |
| Top procesos | `ps` / `top` / `nettop -n` (entitlements propias de esos binarios) |

Detalles, riesgos y hallazgos (p. ej. el truncamiento a 32 bits de
`NET_RT_IFLIST2` en macOS 26 para binarios de terceros) en
[docs/VIABILIDAD.md](docs/VIABILIDAD.md).

## Desarrollo

```bash
./scripts/run-dev.sh          # compila y relanza en la barra de menús
./scripts/build.sh            # build release
./scripts/package.sh 0.6.0    # empaqueta dist/BtoStats.app + zip (firma ad hoc)
swift run BtoStats --sample 3 # verificación de readers por terminal
```

Requisitos: macOS 14+, Apple Silicon, Xcode Command Line Tools.
Sin dependencias externas (SPM puro). No usar App Sandbox (bloquea el SMC).

## Documentación

[Requerimientos](docs/REQUERIMIENTOS.md) ·
[Viabilidad técnica](docs/VIABILIDAD.md) ·
[Arquitectura](docs/ARQUITECTURA.md) ·
[Roadmap](docs/ROADMAP.md)

## Agradecimientos

El enfoque de lectura del SMC y varios patrones de widgets se estudiaron de
[exelban/stats](https://github.com/exelban/stats) (© Serhiy Mytrovtsiy).

## Licencia

**PolyForm Strict 1.0.0** (source-available). En corto:

- ✅ Gratis: ver el código, descargarlo y usarlo para fines personales y no comerciales.
- ❌ Prohibido venderlo o usarlo comercialmente.
- ❌ Prohibido redistribuir copias o publicar versiones modificadas.
- ✍️ ¿Quieres mejorarlo, integrarlo o comercializarlo? Se necesita autorización
  explícita del autor ([btoaldas](https://github.com/btoaldas)). Las contribuciones
  se aceptan solo con aprobación previa.

Texto completo en [LICENSE](LICENSE). 
