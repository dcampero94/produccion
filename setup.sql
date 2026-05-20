-- ============================================================
-- CRM Producción Tecnoden — Setup inicial
-- Ejecutar en el SQL Editor de Supabase (proyecto lernzlbzrgatqkadwhas)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tabla principal: proyectos
-- ------------------------------------------------------------
create table if not exists proyectos (
  id              bigserial primary key,
  cotizacion_id   text unique references cotizaciones(id) on delete set null,
  cotizacion_num  integer,  -- número visible del CRM viejo, para referencia rápida
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  bloqueado       boolean not null default false,

  -- Datos del cliente (heredados de la cotización)
  cliente_nombre        text,
  cliente_telefono      text,
  direccion_instalacion text,
  asesor_original       text,

  -- Pipeline
  estado text not null default 'Pendiente'
    check (estado in ('Pendiente','En trámite','En instalación','Terminado')),

  -- Asignación
  cuadrilla text
    check (cuadrilla in ('Cuadrilla Tecnoden','Cuadrilla Alex','Cuadrilla Javier','Otro')),
  cuadrilla_otro text,

  -- Fechas para el Gantt
  fecha_venta                   date,
  fecha_programada_instalacion  date,
  fecha_inicio_instalacion      date,
  fecha_terminacion             date,

  -- Datos técnicos (manual o por PDF en V1.5)
  kw_sistema      numeric(8,2),
  num_paneles     integer,
  marca_paneles   text,
  modelo_paneles  text,
  marca_inversor  text,
  modelo_inversor text,
  tipo_estructura text,
  notas_tecnicas  text,

  -- Trámite CFE (solo el número; los comentarios van aparte)
  siresi text
);

create index if not exists idx_proyectos_estado    on proyectos(estado);
create index if not exists idx_proyectos_cuadrilla on proyectos(cuadrilla);
create index if not exists idx_proyectos_fechas    on proyectos(fecha_programada_instalacion, fecha_terminacion);

-- Mantener actualizado_en al día
create or replace function fn_proyectos_touch()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

drop trigger if exists trg_proyectos_touch on proyectos;
create trigger trg_proyectos_touch
  before update on proyectos
  for each row execute function fn_proyectos_touch();

-- ------------------------------------------------------------
-- 2. Bitácora del trámite CFE (comentarios sobre el SIRESI)
-- ------------------------------------------------------------
create table if not exists proyecto_comentarios_cfe (
  id          bigserial primary key,
  proyecto_id bigint not null references proyectos(id) on delete cascade,
  autor       text not null,
  comentario  text not null,
  creado_en   timestamptz not null default now()
);

create index if not exists idx_cfe_proyecto on proyecto_comentarios_cfe(proyecto_id, creado_en desc);

-- ------------------------------------------------------------
-- 3. Bitácora general del proyecto (mismo estilo que el CRM viejo)
-- ------------------------------------------------------------
create table if not exists proyecto_comentarios_general (
  id          bigserial primary key,
  proyecto_id bigint not null references proyectos(id) on delete cascade,
  autor       text not null,
  comentario  text not null,
  creado_en   timestamptz not null default now()
);

create index if not exists idx_gen_proyecto on proyecto_comentarios_general(proyecto_id, creado_en desc);

-- ------------------------------------------------------------
-- 4. Trigger: cotización → proyecto
-- ------------------------------------------------------------
-- Se dispara cuando una fila de "cotizaciones" se inserta o actualiza.
-- Si el estado pasa a "Vendida" y no existe proyecto: lo crea.
-- Si una cotización "Vendida" se revierte: bloquea el proyecto.
-- Si vuelve a "Vendida" después de revertirse: lo desbloquea.

create or replace function fn_cotizacion_a_proyecto()
returns trigger language plpgsql as $$
declare
  v_proyecto_id bigint;
begin
  -- Caso 1: pasó a Vendida (o se insertó directo como Vendida)
  if new.estado = 'Vendida'
     and (tg_op = 'INSERT' or old.estado is distinct from 'Vendida')
  then
    select id into v_proyecto_id from proyectos where cotizacion_id = new.id;

    if v_proyecto_id is null then
      insert into proyectos (
        cotizacion_id,
        cotizacion_num,
        cliente_nombre,
        cliente_telefono,
        direccion_instalacion,  -- queda null, se llena manual en el CRM de producción
        asesor_original,
        fecha_venta,
        estado,
        bloqueado
      ) values (
        new.id,
        new.num,
        new.cliente,
        new.telefono,
        null,
        new.asesor,
        coalesce(new."fechaCierre", current_date),
        'Pendiente',
        false
      );
    else
      -- Ya existía pero estaba bloqueado: desbloquear
      update proyectos set bloqueado = false where id = v_proyecto_id;
    end if;
  end if;

  -- Caso 2: salió de Vendida → bloquear su proyecto si existe
  if tg_op = 'UPDATE'
     and old.estado = 'Vendida'
     and new.estado is distinct from 'Vendida'
  then
    update proyectos set bloqueado = true where cotizacion_id = new.id;
  end if;

  return new;
end $$;

drop trigger if exists trg_cotizacion_a_proyecto on cotizaciones;
create trigger trg_cotizacion_a_proyecto
  after insert or update of estado on cotizaciones
  for each row execute function fn_cotizacion_a_proyecto();

-- ------------------------------------------------------------
-- 5. Permisos (mismo patrón que cotizaciones)
-- ------------------------------------------------------------
grant select, insert, update, delete on proyectos                    to anon, authenticated;
grant select, insert, update, delete on proyecto_comentarios_cfe     to anon, authenticated;
grant select, insert, update, delete on proyecto_comentarios_general to anon, authenticated;

grant usage, select on sequence proyectos_id_seq                     to anon, authenticated;
grant usage, select on sequence proyecto_comentarios_cfe_id_seq      to anon, authenticated;
grant usage, select on sequence proyecto_comentarios_general_id_seq  to anon, authenticated;

-- ------------------------------------------------------------
-- 6. Backfill: crear proyectos para las cotizaciones ya Vendidas
-- ------------------------------------------------------------
-- Corre esto UNA vez después de crear el trigger, para no perder las ~30 ventas existentes.
insert into proyectos (cotizacion_id, cotizacion_num, cliente_nombre, cliente_telefono, asesor_original, fecha_venta, estado)
select
  c.id,
  c.num,
  c.cliente,
  c.telefono,
  c.asesor,
  coalesce(c."fechaCierre", current_date),
  'Pendiente'
from cotizaciones c
left join proyectos p on p.cotizacion_id = c.id
where c.estado = 'Vendida'
  and p.id is null;
