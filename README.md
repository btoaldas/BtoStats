# BtoStats

Monitor de sistema propio para la barra de menús de macOS (Apple Silicon).
Una sola app que reemplaza los monitores sueltos de CPU, GPU, temperatura,
ventiladores, RAM, red y disco.

- **Widget**: cuadrícula chiquita en el status item, tiempo real (~1 s),
  celdas configurables (checks por métrica).
- **Panel** (clic): gráficos en vivo, KPIs, top procesos por CPU/RAM/red,
  acciones de liberar RAM y matar procesos.

## Desarrollo

```bash
./scripts/run-dev.sh     # compila y relanza en la barra de menús
./scripts/build.sh       # build release
```

Documentación en `docs/`: requerimientos, viabilidad técnica, arquitectura y roadmap.

## Estado

Fase 0 — esqueleto funcional: status item con CPU % y RAM % reales (2 filas, fuente mono 9 pt),
menú con detalle y salida. Ver `docs/ROADMAP.md`.
