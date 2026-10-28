-- Family Hub foundation schema. Run in Supabase SQL Editor or via Supabase CLI.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) between 1 and 60),
  avatar_color text not null default '#777D61' check (avatar_color ~ '^#[0-9A-Fa-f]{6}$'),
  notification_settings jsonb not null default '{"tasks":true,"shopping":true,"comments":true,"events":true}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One family per account for the first release. Can be relaxed later if multi-family support is required.
create table if not exists public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  display_name text not null check (char_length(display_name) between 1 and 60),
  avatar_color text not null default '#777D61' check (avatar_color ~ '^#[0-9A-Fa-f]{6}$'),
  joined_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  removed_at timestamptz,
  unique (family_id, user_id)
);
create index if not exists family_members_family_idx on public.family_members(family_id) where removed_at is null;

create table if not exists public.family_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  code_hash text not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  max_uses integer not null default 1 check (max_uses between 1 and 20),
  uses integer not null default 0 check (uses >= 0),
  revoked_at timestamptz,
  check (expires_at > created_at)
);
create index if not exists family_invites_family_idx on public.family_invites(family_id);

create table if not exists public.family_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name_snapshot text not null,
  event_type text not null check (char_length(event_type) between 1 and 80),
  entity_type text not null check (char_length(entity_type) between 1 and 80),
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists family_events_recent_idx on public.family_events(family_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end; $$;
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists families_updated_at on public.families;
create trigger families_updated_at before update on public.families for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  v_name := left(trim(coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), 'Участник')), 60);
  if char_length(v_name) < 1 then v_name := 'Участник'; end if;
  insert into public.profiles(id, display_name) values (new.id, v_name) on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_active_family_member(p_family_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.family_members fm where fm.family_id = p_family_id and fm.user_id = auth.uid() and fm.removed_at is null);
$$;
create or replace function public.is_family_owner(p_family_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.family_members fm where fm.family_id = p_family_id and fm.user_id = auth.uid() and fm.role = 'owner' and fm.removed_at is null);
$$;
revoke all on function public.is_active_family_member(uuid) from public;
revoke all on function public.is_family_owner(uuid) from public;
grant execute on function public.is_active_family_member(uuid) to authenticated;
grant execute on function public.is_family_owner(uuid) to authenticated;

create or replace function public.create_family(p_family_name text, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_family_id uuid; v_name text := trim(p_family_name); v_display text := trim(p_display_name);
begin
  if v_uid is null then raise exception 'Требуется авторизация'; end if;
  if char_length(v_name) not between 1 and 80 then raise exception 'Название семьи должно содержать от 1 до 80 символов'; end if;
  if char_length(v_display) not between 1 and 60 then raise exception 'Имя должно содержать от 1 до 60 символов'; end if;
  if exists(select 1 from public.family_members where user_id = v_uid and removed_at is null) then raise exception 'У аккаунта уже есть семейное пространство'; end if;
  insert into public.profiles(id, display_name) values (v_uid, v_display) on conflict (id) do update set display_name = excluded.display_name;
  insert into public.families(name, created_by) values (v_name, v_uid) returning id into v_family_id;
  insert into public.family_members(family_id, user_id, role, display_name) values (v_family_id, v_uid, 'owner', v_display);
  insert into public.family_events(family_id, actor_id, actor_name_snapshot, event_type, entity_type, entity_id, details)
  values (v_family_id, v_uid, v_display, 'family.created', 'family', v_family_id, jsonb_build_object('name', v_name));
  return v_family_id;
end; $$;
revoke all on function public.create_family(text,text) from public;
grant execute on function public.create_family(text,text) to authenticated;

create or replace function public.create_family_invite(p_expires_in_hours integer default 72, p_max_uses integer default 1)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_family_id uuid; v_code text; v_name text;
begin
  if v_uid is null then raise exception 'Требуется авторизация'; end if;
  if p_expires_in_hours not between 1 and 720 then raise exception 'Срок приглашения должен быть от 1 часа до 30 дней'; end if;
  if p_max_uses not between 1 and 20 then raise exception 'Недопустимое количество использований'; end if;
  select family_id, display_name into v_family_id, v_name from public.family_members where user_id = v_uid and role = 'owner' and removed_at is null;
  if v_family_id is null then raise exception 'Создать приглашение может только владелец семьи'; end if;
  v_code := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.family_invites(family_id, code_hash, created_by, expires_at, max_uses)
  values (v_family_id, encode(extensions.digest(v_code, 'sha256'), 'hex'), v_uid, now() + make_interval(hours => p_expires_in_hours), p_max_uses);
  insert into public.family_events(family_id, actor_id, actor_name_snapshot, event_type, entity_type, details)
  values (v_family_id, v_uid, v_name, 'invite.created', 'invite', jsonb_build_object('expires_in_hours', p_expires_in_hours, 'max_uses', p_max_uses));
  return v_code;
end; $$;
revoke all on function public.create_family_invite(integer,integer) from public;
grant execute on function public.create_family_invite(integer,integer) to authenticated;

create or replace function public.join_family_by_invite(p_invite_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_hash text; v_invite public.family_invites%rowtype; v_family_name text;
begin
  if v_uid is null then raise exception 'Требуется авторизация'; end if;
  if char_length(coalesce(p_invite_code,'')) not between 32 and 128 then raise exception 'Неверный код приглашения'; end if;
  if char_length(trim(coalesce(p_display_name,''))) not between 1 and 60 then raise exception 'Имя должно содержать от 1 до 60 символов'; end if;
  if exists(select 1 from public.family_members where user_id = v_uid and removed_at is null) then raise exception 'У аккаунта уже есть семейное пространство'; end if;
  v_hash := encode(extensions.digest(trim(p_invite_code), 'sha256'), 'hex');
  select * into v_invite from public.family_invites where code_hash = v_hash and revoked_at is null and expires_at > now() and uses < max_uses for update;
  if not found then raise exception 'Приглашение недействительно, истекло или уже использовано'; end if;
  select name into v_family_name from public.families where id = v_invite.family_id;
  insert into public.profiles(id, display_name) values (v_uid, trim(p_display_name)) on conflict (id) do update set display_name = excluded.display_name;
  insert into public.family_members(family_id, user_id, role, display_name) values (v_invite.family_id, v_uid, 'member', trim(p_display_name));
  update public.family_invites set uses = uses + 1 where id = v_invite.id;
  insert into public.family_events(family_id, actor_id, actor_name_snapshot, event_type, entity_type, details)
  values (v_invite.family_id, v_uid, trim(p_display_name), 'member.joined', 'member', jsonb_build_object('family_name', v_family_name));
  return v_invite.family_id;
end; $$;
revoke all on function public.join_family_by_invite(text,text) from public;
grant execute on function public.join_family_by_invite(text,text) to authenticated;

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;
alter table public.family_events enable row level security;

drop policy if exists "profiles read self or family" on public.profiles;
create policy "profiles read self or family" on public.profiles for select to authenticated using (id = auth.uid() or exists(select 1 from public.family_members mine join public.family_members theirs on theirs.family_id = mine.family_id where mine.user_id = auth.uid() and mine.removed_at is null and theirs.user_id = profiles.id and theirs.removed_at is null));
drop policy if exists "profiles update self" on public.profiles;
create policy "profiles update self" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "profiles insert self" on public.profiles;
create policy "profiles insert self" on public.profiles for insert to authenticated with check (id = auth.uid());

drop policy if exists "families read active members" on public.families;
create policy "families read active members" on public.families for select to authenticated using (public.is_active_family_member(id));
drop policy if exists "families update owner" on public.families;
create policy "families update owner" on public.families for update to authenticated using (public.is_family_owner(id)) with check (public.is_family_owner(id));

drop policy if exists "members read same family" on public.family_members;
create policy "members read same family" on public.family_members for select to authenticated using (public.is_active_family_member(family_id));
drop policy if exists "members update own profile fields" on public.family_members;
create policy "members update own profile fields" on public.family_members for update to authenticated using (user_id = auth.uid() and removed_at is null) with check (user_id = auth.uid() and removed_at is null and role = (select fm.role from public.family_members fm where fm.user_id = auth.uid() and fm.family_id = family_members.family_id));

-- Raw invitation hashes and management stay server-side. Client receives the raw code only from create_family_invite RPC.
drop policy if exists "invites owner read" on public.family_invites;
create policy "invites owner read" on public.family_invites for select to authenticated using (public.is_family_owner(family_id));
drop policy if exists "events read family" on public.family_events;
create policy "events read family" on public.family_events for select to authenticated using (public.is_active_family_member(family_id));
-- No direct insert/update/delete policies on audit events: records are written by trusted database functions.

grant select, insert, update on public.profiles to authenticated;
grant select on public.families to authenticated;
grant update on public.families to authenticated;
grant select, update on public.family_members to authenticated;
grant select on public.family_invites to authenticated;
grant select on public.family_events to authenticated;

-- Realtime publishes only metadata/events. Add tables in Supabase Dashboard if not already included.
do $$ begin
  alter publication supabase_realtime add table public.family_members;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.family_events;
exception when duplicate_object then null; when undefined_object then null; end $$;
