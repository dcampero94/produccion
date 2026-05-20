-- ============================================================
-- v1.3 — Separar estado en dos campos: instalación y trámite CFE
-- ============================================================
-- IMPORTANTE: este script preserva todos los datos existentes.
-- La columna `estado` original NO se borra; queda como respaldo
-- por si hay que revertir.

-- 1. Agregar nuevas columnas
alter table proyectos add column if not exists estado_instalacion text default 'Pendiente'
  check (estado_instalacion in ('Pendiente','Programada','En instalación','Instalada'));

alter table proyectos add column if not exists estado_tramite text default 'Sin iniciar'
  check (estado_tramite in ('Sin iniciar','En trámite','Aprobado','N/A'));

-- 2. Migración automática del estado actual
-- Pendiente       → instalacion=Pendiente,        tramite=Sin iniciar
-- En trámite      → instalacion=Pendiente,        tramite=En trámite
-- En instalación  → instalacion=En instalación,   tramite=En trámite
-- Terminado       → instalacion=Instalada,        tramite=Aprobado

update proyectos set
  estado_instalacion = case
    when estado = 'Pendiente'      then 'Pendiente'
    when estado = 'En trámite'     then 'Pendiente'
    when estado = 'En instalación' then 'En instalación'
    when estado = 'Terminado'      then 'Instalada'
    else 'Pendiente'
  end,
  estado_tramite = case
    when estado = 'Pendiente'      then 'Sin iniciar'
    when estado = 'En trámite'     then 'En trámite'
    when estado = 'En instalación' then 'En trámite'
    when estado = 'Terminado'      then 'Aprobado'
    else 'Sin iniciar'
  end
where estado_instalacion = 'Pendiente' and estado_tramite = 'Sin iniciar';
-- La cláusula where evita re-migrar si corres el script dos veces

-- 3. Índices para los filtros
create index if not exists idx_proyectos_estado_inst    on proyectos(estado_instalacion);
create index if not exists idx_proyectos_estado_tramite on proyectos(estado_tramite);

-- 4. Actualizar el trigger para que use los nuevos campos al crear proyectos
create or replace function fn_cotizacion_a_proyecto()
returns trigger language plpgsql as $$
declare
  v_proyecto_id bigint;
begin
  if new.estado = 'Vendida'
     and (tg_op = 'INSERT' or old.estado is distinct from 'Vendida')
  then
    select id into v_proyecto_id from proyectos where cotizacion_id = new.id;

    if v_proyecto_id is null then
      insert into proyectos (
        cotizacion_id, cotizacion_num,
        cliente_nombre, cliente_telefono, asesor_original,
        fecha_venta,
        estado, estado_instalacion, estado_tramite,
        bloqueado
      ) values (
        new.id, new.num,
        new.cliente, new.telefono, new.asesor,
        coalesce(new."fechaCierre", current_date),
        'Pendiente', 'Pendiente', 'Sin iniciar',
        false
      );
    else
      update proyectos set bloqueado = false where id = v_proyecto_id;
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.estado = 'Vendida'
     and new.estado is distinct from 'Vendida'
  then
    update proyectos set bloqueado = true where cotizacion_id = new.id;
  end if;

  return new;
end $$;
