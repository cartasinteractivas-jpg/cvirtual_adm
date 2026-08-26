-- =============================================================================
-- CVIRTUAL ADM — ACCESO DE CLIENTE, ADMINISTRACIÓN, RENOVACIONES Y QR
-- Ejecutar después de 001_cv_virtual_schema.sql y 002_supabase_storage_media.sql.
-- =============================================================================

begin;

-- Clasifica el motivo de cada pago sin modificar el historial existente.
alter table public.candidate_payments
  add column if not exists service_type text not null default 'initial_registration'
  check (service_type in ('initial_registration', 'renewal_6m', 'video_change', 'other'));

create index if not exists candidate_payments_service_idx
  on public.candidate_payments (candidate_id, service_type, created_at desc);

-- Solicitud de vínculo entre el correo con el que el cliente inicia sesión y
-- el perfil registrado originalmente desde la aplicación pública.
create table if not exists public.client_profile_access_requests (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  request_status text not null default 'pending' check (request_status in ('pending', 'approved', 'rejected')),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (candidate_id, user_id)
);

create index if not exists client_profile_access_requests_status_idx
  on public.client_profile_access_requests (request_status, created_at desc);

alter table public.client_profile_access_requests enable row level security;
grant select, insert on public.client_profile_access_requests to authenticated;
grant update on public.client_profile_access_requests to authenticated;

drop policy if exists client_access_request_own_or_admin on public.client_profile_access_requests;
create policy client_access_request_own_or_admin
on public.client_profile_access_requests
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_staff(array['admin']::public.staff_role[])));

drop policy if exists client_access_request_create_own on public.client_profile_access_requests;
create policy client_access_request_create_own
on public.client_profile_access_requests
for insert to authenticated
with check (user_id = (select auth.uid()) and request_status = 'pending');

drop policy if exists client_access_request_admin_review on public.client_profile_access_requests;
create policy client_access_request_admin_review
on public.client_profile_access_requests
for update to authenticated
using ((select private.is_staff(array['admin']::public.staff_role[])))
with check ((select private.is_staff(array['admin']::public.staff_role[])));

-- El cliente solicita acceso usando el mismo correo que dejó al registrarse.
create or replace function public.request_client_profile_access(p_email text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_candidate_id uuid;
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_request_id uuid;
begin
  if auth.uid() is null or v_email = '' then
    raise exception 'Debe iniciar sesión con un correo válido';
  end if;
  if lower(trim(p_email)) <> v_email then
    raise exception 'Use el mismo correo con el que inició sesión';
  end if;
  select cp.id into v_candidate_id
  from public.candidate_profiles cp
  where lower(cp.email) = v_email
  order by cp.created_at desc
  limit 1;
  if v_candidate_id is null then
    raise exception 'No encontramos un perfil registrado con este correo';
  end if;
  insert into public.client_profile_access_requests (candidate_id, user_id, email)
  values (v_candidate_id, auth.uid(), v_email)
  on conflict (candidate_id, user_id) do update
    set request_status = case when client_profile_access_requests.request_status = 'rejected' then 'pending' else client_profile_access_requests.request_status end,
        reviewed_at = null,
        reviewed_by = null
  returning id into v_request_id;
  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (v_candidate_id, 'client_access_requested', 'Solicitud de acceso de cliente', v_email || ' solicitó administrar su perfil.');
  return v_request_id;
end;
$$;

-- Administración aprueba el vínculo: desde ese momento el cliente puede editar
-- sus datos con RLS, pero no puede cambiar QR, estado, pagos ni publicación.
create or replace function public.admin_grant_client_profile_access(p_request_id uuid, p_approve boolean)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_request public.client_profile_access_requests%rowtype;
begin
  if not private.is_staff(array['admin']::public.staff_role[]) then
    raise exception 'Solo administración puede aprobar accesos';
  end if;
  select * into v_request from public.client_profile_access_requests where id = p_request_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  update public.client_profile_access_requests
  set request_status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_at = now(), reviewed_by = auth.uid()
  where id = p_request_id;
  if p_approve then
    update public.candidate_profiles set owner_user_id = v_request.user_id where id = v_request.candidate_id;
  end if;
  return v_request.candidate_id;
end;
$$;

-- Activa o desactiva la lectura del QR. El contenido público se mantiene en
-- construcción si el perfil no está publicado o si el QR queda desactivado.
create or replace function public.admin_set_qr_enabled(p_candidate_id uuid, p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo administración o publicación puede cambiar el QR';
  end if;
  update public.candidate_qr_codes
  set is_active = p_enabled,
      revoked_at = case when p_enabled then null else now() end
  where candidate_id = p_candidate_id;
  if not found then raise exception 'QR no encontrado'; end if;
  insert into public.audit_events (actor_user_id, candidate_id, event_type, new_data)
  values (auth.uid(), p_candidate_id, 'qr_availability_changed', jsonb_build_object('enabled', p_enabled));
  return p_enabled;
end;
$$;

-- Registra servicios según la lista comercial solicitada y extiende la vigencia
-- solo para la alta inicial y la renovación semestral.
create or replace function public.admin_record_service_payment(p_candidate_id uuid, p_service_type text)
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_amount numeric(12,2);
  v_expiration timestamptz;
begin
  if not private.is_staff(array['admin', 'finance']::public.staff_role[]) then
    raise exception 'Solo administración o finanzas puede registrar pagos';
  end if;
  v_amount := case p_service_type
    when 'initial_registration' then 40.00
    when 'renewal_6m' then 20.00
    when 'video_change' then 10.00
    else null
  end;
  if v_amount is null then raise exception 'Tipo de servicio inválido'; end if;
  select expires_at into v_expiration from public.candidate_profiles where id = p_candidate_id for update;
  if not found then raise exception 'Perfil no encontrado'; end if;
  if p_service_type in ('initial_registration', 'renewal_6m') then
    v_expiration := greatest(coalesce(v_expiration, now()), now()) + interval '6 months';
    update public.candidate_profiles set expires_at = v_expiration where id = p_candidate_id;
  end if;
  insert into public.candidate_payments (
    candidate_id, method, amount, currency, payment_status, yape_operation_code,
    verification_note, verified_at, verified_by, service_type, metadata
  ) values (
    p_candidate_id, 'other', v_amount, 'PEN', 'paid', 'ADM-' || replace(gen_random_uuid()::text, '-', ''),
    'Registrado desde cvirtual_adm', now(), auth.uid(), p_service_type,
    jsonb_build_object('origin', 'cvirtual_adm')
  );
  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (p_candidate_id, 'service_payment_recorded', 'Servicio registrado', p_service_type || ' · S/ ' || v_amount::text);
  return v_expiration;
end;
$$;

-- El administrador carga el video ya editado: primero queda listo y privado.
create or replace function public.admin_mark_media_ready(p_media_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_candidate_id uuid;
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo administración o publicación puede revisar videos';
  end if;
  update public.candidate_media
  set media_status = 'ready', visibility = 'private'
  where id = p_media_id
    and (metadata ->> 'storage_provider') = 'supabase_storage'
  returning candidate_id into v_candidate_id;
  if v_candidate_id is null then raise exception 'Medio no encontrado'; end if;
  return v_candidate_id;
end;
$$;

-- Antes de publicar, toma el video más reciente listo como fondo público.
create or replace function public.admin_prepare_latest_media_background(p_candidate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_media_id uuid;
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo administración o publicación puede preparar videos';
  end if;
  if not exists (select 1 from public.candidate_profiles where id = p_candidate_id and status = 'approved') then
    raise exception 'El perfil debe estar aprobado antes de preparar el video público';
  end if;
  select id into v_media_id from public.candidate_media
  where candidate_id = p_candidate_id and media_type = 'video' and media_status = 'ready'
  order by uploaded_at desc limit 1 for update;
  if v_media_id is null then raise exception 'No hay video editado listo para publicar'; end if;
  update public.candidate_media set is_background = false where candidate_id = p_candidate_id and is_background;
  update public.candidate_media set is_background = true, visibility = 'public' where id = v_media_id;
  return v_media_id;
end;
$$;

revoke all on function public.request_client_profile_access(text) from public;
revoke all on function public.admin_grant_client_profile_access(uuid, boolean) from public;
revoke all on function public.admin_set_qr_enabled(uuid, boolean) from public;
revoke all on function public.admin_record_service_payment(uuid, text) from public;
revoke all on function public.admin_mark_media_ready(uuid) from public;
revoke all on function public.admin_prepare_latest_media_background(uuid) from public;
grant execute on function public.request_client_profile_access(text) to authenticated;
grant execute on function public.admin_grant_client_profile_access(uuid, boolean) to authenticated;
grant execute on function public.admin_set_qr_enabled(uuid, boolean) to authenticated;
grant execute on function public.admin_record_service_payment(uuid, text) to authenticated;
grant execute on function public.admin_mark_media_ready(uuid) to authenticated;
grant execute on function public.admin_prepare_latest_media_background(uuid) to authenticated;

commit;

-- CONFIGURACIÓN DEL PRIMER ADMINISTRADOR (ejecutar tras crear el usuario en
-- Supabase Authentication con un correo real y la contraseña que tú elijas):
-- insert into public.staff_roles (user_id, role)
-- select id, 'admin'::public.staff_role
-- from auth.users where lower(email) = lower('TU_CORREO_ADMIN@EJEMPLO.COM')
-- on conflict (user_id, role) do update set is_active = true;
