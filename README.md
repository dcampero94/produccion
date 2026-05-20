# CRM Producción Tecnoden

Seguimiento de proyectos de instalación solar. Se alimenta automáticamente de las cotizaciones marcadas como "Vendida" en el [CRM de cotizaciones](https://github.com/dcampero94/crm-cotizaciones).

**Producción:** `produccion.tecnoden.com` (GitHub Pages)

## Stack

- HTML / CSS / JS puros (sin framework)
- Supabase (mismo proyecto: `lernzlbzrgatqkadwhas`)
- GitHub Pages para hosting

## Estructura

```
crm-produccion/
├── index.html        # Login + vista Gantt + tabla + detalle del proyecto
├── README.md
└── setup.sql         # Ejecutar UNA vez en Supabase para crear tablas y triggers
```

Una sola página. Si escala, se parte.

## Setup inicial

1. **Ejecutar `setup.sql`** en el SQL Editor de Supabase. Esto crea:
   - Tabla `proyectos`
   - Tablas `proyecto_comentarios_cfe` y `proyecto_comentarios_general`
   - Trigger `trg_cotizacion_a_proyecto` (cotización → proyecto automático)
   - Permisos para `anon` y `authenticated`
   - Backfill de las cotizaciones ya Vendidas

   El SQL está ajustado para los nombres reales de columnas del CRM viejo: `id` (text), `num`, `cliente`, `telefono`, `asesor`, `estado`, `fechaCierre`. La dirección de instalación no existe en `cotizaciones` y se llena manualmente en el CRM de Producción.

2. **Configurar el subdominio en GitHub Pages:**
   - Settings → Pages → Custom domain → `produccion.tecnoden.com`
   - DNS: agregar CNAME `produccion` → `dcampero94.github.io`

## Modelo de datos

**proyectos** (una fila por proyecto)
- Identidad: `id`, `cotizacion_id` (text, FK a cotizaciones), `cotizacion_num` (referencia visible), `creado_en`, `bloqueado`
- Cliente (heredados): `cliente_nombre`, `cliente_telefono`, `direccion_instalacion`, `asesor_original`
- Pipeline: `estado` (Pendiente / En trámite / En instalación / Terminado)
- Asignación: `cuadrilla`, `cuadrilla_otro`
- Fechas Gantt: `fecha_venta`, `fecha_programada_instalacion`, `fecha_inicio_instalacion`, `fecha_terminacion`
- Técnicos: `kw_sistema`, `num_paneles`, `marca_paneles`, `modelo_paneles`, `marca_inversor`, `modelo_inversor`, `tipo_estructura`, `notas_tecnicas`
- CFE: `siresi`

**proyecto_comentarios_cfe** — bitácora del trámite (autor, comentario, fecha).
**proyecto_comentarios_general** — bitácora general del proyecto.

Separar las dos bitácoras es a propósito: SIRESI es regulatorio/técnico y se consulta aparte del ruido del proyecto.

## Reglas del trigger

- Cotización pasa a **Vendida** → se crea proyecto en estado *Pendiente* (o se desbloquea si ya existía).
- Cotización Vendida cambia a cualquier otro estado → su proyecto se **bloquea** (read-only en la UI). No se borra porque el cobro ya ocurrió.
- Si vuelve a Vendida → se desbloquea.

## Usuarios V1

Hardcoded en el HTML (mismo patrón que el CRM viejo):

| Usuario  | Contraseña    | Rol      |
|----------|---------------|----------|
| German   | (definir)     | admin V1 |
| Daniel   | (definir)     | admin V1 |
| SGerman  | (definir)     | admin V1 |

Juan (supervisor) y separación por roles → V1.5.

## Roadmap

- **V1** — lo que está aquí: pipeline, Gantt, bitácoras, trigger.
- **V1.5** — carga de PDF de cotización con Gemini para autocompletar campos técnicos (paneles, inversor). Requiere Edge Function de Supabase para no exponer la API key.
- **V2** — roles diferenciados (asesor, instalador, admin), Storage para fotos y contratos, notificaciones.
