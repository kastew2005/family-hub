-- Family Hub final hardening: permissions, member removal, audit coverage and profile metadata.
-- Run after schema.sql and migrations/202610280002_family_features.sql.

-- The client can never edit membership identity/role. Trusted SECURITY DEFINER RPCs may perform removal.
create or replace function public.protect_membership_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user = 'postgres' then return new; end if;
  if new.user_id is distinct from old.user_id
     or new.family_id is distinct from old.family_id
     or new.role is distinct from old.role
     or new.removed_at is distinct from old.removed_at then
    raise exception 'Поля доступа участника нельзя изменять напрямую';
  end if;
  return new;
end; $$;

create or replace function public.remove_family_member(p_member_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_family uuid; v_name text; v_member_name text; v_member_id uuid;
begin
  if auth.uid() is null then raise exception 'Требуется авторизация'; end if;
  select family_id, display_name into v_family, v_name
    from public.family_members where user_id = auth.uid() and role = 'owner' and removed_at is null;
  if v_family is null then raise exception 'Только владелец может управлять участниками'; end if;
  if p_member_user_id = auth.uid() then raise exception 'Нельзя удалить владельца из его собственного пространства'; end if;
  select display_name, id into v_member_name, v_member_id from public.family_members
    where family_id = v_family and user_id = p_member_user_id and removed_at is null for update;
  if v_member_name is null then raise exception 'Участник не найден'; end if;
  update public.tasks set assignee_id = null where family_id = v_family and assignee_id = p_member_user_id;
  update public.calendar_events set participant_ids = array_remove(participant_ids, p_member_user_id) where family_id = v_family and p_member_user_id = any(participant_ids);
  delete from public.family_members where family_id = v_family and user_id = p_member_user_id;
  insert into public.family_events(family_id, actor_id, actor_name_snapshot, event_type, entity_type, entity_id, details)
    values (v_family, auth.uid(), v_name, 'member.removed', 'member', v_member_id, jsonb_build_object('member_name', v_member_name));
end; $$;
revoke all on function public.remove_family_member(uuid) from public;
grant execute on function public.remove_family_member(uuid) to authenticated;

-- Explicit grants keep table access predictable across projects with customized default privileges.
grant select, insert, update, delete on public.task_categories to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select on public.task_completion_history to authenticated;
grant select, insert, update, delete on public.shopping_items to authenticated;
grant select, insert, update, delete on public.item_comments to authenticated;
grant select, insert, delete on public.comment_reactions to authenticated;
grant select, insert, update, delete on public.calendar_events to authenticated;
grant select on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;
grant select, insert, update, delete on public.family_notes to authenticated;
grant select, insert, delete on public.task_templates to authenticated;
grant select on public.family_events to authenticated;

-- Ensure every family-owned table remains RLS protected and the audit log is read-only to clients.
alter table public.task_categories enable row level security;
alter table public.tasks enable row level security;
alter table public.task_completion_history enable row level security;
alter table public.shopping_items enable row level security;
alter table public.item_comments enable row level security;
alter table public.comment_reactions enable row level security;
alter table public.calendar_events enable row level security;
alter table public.notifications enable row level security;
alter table public.family_notes enable row level security;
alter table public.task_templates enable row level security;
alter table public.family_events enable row level security;
revoke insert, update, delete on public.family_events from anon, authenticated;
revoke insert, update, delete on public.task_completion_history from anon, authenticated;

-- Server timestamps and author identity are not accepted from the browser.
create or replace function public.protect_note_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.family_id is distinct from old.family_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Автор, семья и время создания заметки защищены';
  end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end; $$;

-- Audit notes and preserve actor/time as server-owned event metadata.
drop trigger if exists notes_audit on public.family_notes;
create trigger notes_audit after insert or update or delete on public.family_notes
for each row execute function public.audit_family_change();

-- Profiles are private to their owner and active family; do not let a user alter the identity key.
create or replace function public.protect_profile_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception 'Идентификатор и время создания профиля защищены';
  end if;
  new.updated_at := now();
  return new;
end; $$;
drop trigger if exists profiles_protect_identity on public.profiles;
create trigger profiles_protect_identity before update on public.profiles
for each row execute function public.protect_profile_identity();

-- Existing families receive the built-in categories idempotently.
insert into public.task_categories(family_id, name, is_default, sort_order, created_by)
select f.id, c.name, true, c.sort_order, f.created_by
from public.families f
cross join (values
  ('Список покупок',10), ('Уборка и порядок',20), ('Домашние обязанности',30), ('Поручения',40),
  ('Ремонт и обслуживание',50), ('Семейные дела',60), ('Учёба и работа',70), ('Другое',80)
) as c(name, sort_order)
on conflict (family_id, name) do nothing;

-- Tighten deletion predicates: a formerly associated user cannot mutate a family after removal.
drop policy if exists calendar_delete on public.calendar_events;
create policy calendar_delete on public.calendar_events for delete to authenticated
using (public.is_active_family_member(family_id) and (created_by = auth.uid() or public.is_family_owner(family_id)));
drop policy if exists notes_delete on public.family_notes;
create policy notes_delete on public.family_notes for delete to authenticated
using (public.is_active_family_member(family_id) and (created_by = auth.uid() or public.is_family_owner(family_id)));
drop policy if exists templates_delete on public.task_templates;
create policy templates_delete on public.task_templates for delete to authenticated
using (public.is_active_family_member(family_id) and (created_by = auth.uid() or public.is_family_owner(family_id)));
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated
using (user_id = auth.uid() and public.is_active_family_member(family_id))
with check (user_id = auth.uid() and public.is_active_family_member(family_id));

create or replace function public.protect_server_fields() returns trigger language plpgsql set search_path = '' as $$
begin
 if current_user <> 'postgres' then
  if tg_table_name = 'tasks' and (
    new.id is distinct from old.id or new.family_id is distinct from old.family_id or
    new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or
    new.created_at is distinct from old.created_at or new.completed_by is distinct from old.completed_by or
    new.completed_at is distinct from old.completed_at or
    (new.status is distinct from old.status and (old.status = 'completed' or new.status = 'completed'))
  ) then raise exception 'Автор, идентификатор, семья и данные выполнения защищены сервером'; end if;
  if tg_table_name = 'shopping_items' and (
    new.id is distinct from old.id or new.family_id is distinct from old.family_id or
    new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or
    new.created_at is distinct from old.created_at or new.bought_by is distinct from old.bought_by or
    new.buyer_name is distinct from old.buyer_name or new.bought_at is distinct from old.bought_at
  ) then raise exception 'Автор, идентификатор, семья и данные покупки защищены сервером'; end if;
 end if;
 return new;
end; $$;

create or replace function public.protect_comment_integrity() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_family uuid;
begin
 if tg_op = 'UPDATE' then
  if new.id is distinct from old.id or new.family_id is distinct from old.family_id or
     new.entity_type is distinct from old.entity_type or new.entity_id is distinct from old.entity_id or
     new.author_id is distinct from old.author_id or new.author_name is distinct from old.author_name or
     new.author_avatar_color is distinct from old.author_avatar_color or new.created_at is distinct from old.created_at or
     new.parent_id is distinct from old.parent_id then
    raise exception 'Автор, идентификатор и контекст комментария защищены';
  end if;
  new.edited_at := now();
 end if;
 if tg_op = 'INSERT' then
  if new.entity_type = 'task' then select family_id into v_family from public.tasks where id = new.entity_id;
  elsif new.entity_type = 'shopping' then select family_id into v_family from public.shopping_items where id = new.entity_id;
  else select family_id into v_family from public.calendar_events where id = new.entity_id; end if;
  if v_family is null or v_family <> new.family_id then raise exception 'Объект обсуждения не найден в этой семье'; end if;
  if new.parent_id is not null and not exists(select 1 from public.item_comments p where p.id = new.parent_id and p.family_id = new.family_id and p.entity_type = new.entity_type and p.entity_id = new.entity_id) then raise exception 'Ответ должен относиться к этому обсуждению'; end if;
 end if;
 return new;
end; $$;

create or replace function public.protect_note_identity() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.family_id is distinct from old.family_id or
     new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'Идентификатор, автор, семья и время создания заметки защищены';
  end if;
  new.updated_by := auth.uid(); new.updated_at := now(); return new;
end; $$;

create or replace function public.protect_calendar_identity() returns trigger language plpgsql set search_path = '' as $$
begin
 if current_user <> 'postgres' and (new.id is distinct from old.id or new.family_id is distinct from old.family_id or
    new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or
    new.created_at is distinct from old.created_at) then raise exception 'Идентификатор, автор и время создания события защищены'; end if;
 return new;
end; $$;

-- Atomic profile update keeps the global profile and the family-visible member name aligned.
create or replace function public.update_my_profile(p_display_name text, p_avatar_color text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_name text := trim(coalesce(p_display_name, ''));
begin
  if v_uid is null then raise exception 'Требуется авторизация'; end if;
  if char_length(v_name) not between 1 and 60 then raise exception 'Имя должно содержать от 1 до 60 символов'; end if;
  if p_avatar_color is not null and p_avatar_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Недопустимый цвет аватара'; end if;
  update public.profiles set display_name = v_name, avatar_color = coalesce(p_avatar_color, avatar_color) where id = v_uid;
  update public.family_members set display_name = v_name, avatar_color = coalesce(p_avatar_color, avatar_color)
    where user_id = v_uid and removed_at is null;
end; $$;
revoke all on function public.update_my_profile(text,text) from public;
grant execute on function public.update_my_profile(text,text) to authenticated;

-- Create the next task instance transactionally and idempotently when a recurring task is completed.
create or replace function public.complete_task(p_task_id uuid) returns public.tasks language plpgsql security definer set search_path = '' as $$
declare v_task public.tasks%rowtype; v_next timestamptz; v_root uuid; v_key text; v_type text; i integer;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found or not public.is_active_family_member(v_task.family_id) then raise exception 'Задача не найдена'; end if;
  if v_task.status = 'cancelled' then raise exception 'Отменённую задачу нельзя выполнить'; end if;
  if v_task.status = 'completed' then raise exception 'Задача уже выполнена'; end if;
  if v_task.assignee_id is not null and v_task.assignee_id <> auth.uid() and not public.is_family_owner(v_task.family_id) then raise exception 'Задача назначена другому участнику'; end if;
  update public.tasks set status = 'completed', completed_by = auth.uid(), completed_at = now()
    where id = p_task_id returning * into v_task;
  insert into public.task_completion_history(task_id, family_id, completed_by, completed_at)
    values (v_task.id, v_task.family_id, auth.uid(), v_task.completed_at);
  v_type := coalesce(v_task.recurrence->>'type', 'none');
  if v_type in ('daily','weekly','monthly','weekdays') then
    v_next := coalesce(v_task.due_at, v_task.completed_at);
    if v_type = 'daily' then v_next := v_next + interval '1 day';
    elsif v_type = 'weekly' then v_next := v_next + interval '1 week';
    elsif v_type = 'monthly' then v_next := (v_next + interval '1 month');
    elsif jsonb_typeof(v_task.recurrence->'days') = 'array' and jsonb_array_length(v_task.recurrence->'days') > 0 then
      for i in 1..7 loop
        v_next := v_next + interval '1 day';
        exit when exists (select 1 from jsonb_array_elements_text(v_task.recurrence->'days') d where d::integer = extract(dow from v_next)::integer);
      end loop;
    else v_next := null; end if;
    if v_next is not null then
    v_root := coalesce(v_task.recurrence_root_id, v_task.id);
    v_key := to_char(v_next at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    insert into public.tasks(family_id, title, description, category_id, category_name, created_by, creator_name, assignee_id, due_at, priority, status, recurrence, recurrence_root_id, recurrence_key)
    values (v_task.family_id, v_task.title, v_task.description, v_task.category_id, v_task.category_name, auth.uid(), '', v_task.assignee_id, v_next, v_task.priority, 'new', v_task.recurrence, v_root, v_key)
    on conflict (family_id, recurrence_root_id, recurrence_key) do nothing;
    end if;
  end if;
  return v_task;
end; $$;
revoke all on function public.complete_task(uuid) from public;
grant execute on function public.complete_task(uuid) to authenticated;

-- Notification preferences are respected by the server-side fan-out trigger.
create or replace function public.notify_family_members() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := auth.uid(); v_title text; v_family uuid; v_entity uuid; v_kind text; v_actor_name text; v_entity_type text; v_pref text;
begin
  v_family := new.family_id; v_entity := new.id;
  if tg_table_name = 'tasks' then
    if tg_op = 'UPDATE' and old.status is not distinct from new.status then return new; end if;
    v_kind := 'task'; v_pref := 'tasks'; v_entity_type := 'task';
    v_title := case when new.status = 'completed' then 'Задача выполнена: ' || new.title when tg_op = 'UPDATE' then 'Задача обновлена: ' || new.title else 'Новая задача: ' || new.title end;
  elsif tg_table_name = 'shopping_items' then
    if tg_op = 'UPDATE' and old.bought_at is not distinct from new.bought_at then return new; end if;
    v_kind := 'shopping'; v_pref := 'shopping'; v_entity_type := 'shopping';
    v_title := case when new.bought_at is not null then 'Товар куплен: ' || new.title else 'Товар возвращён в список: ' || new.title end;
  elsif tg_table_name = 'calendar_events' then
    if new.recurrence_root_id is not null then return new; end if;
    v_kind := 'event'; v_pref := 'events'; v_entity_type := 'event'; v_title := 'Семейное событие: ' || new.title;
  elsif tg_table_name = 'item_comments' then
    v_kind := 'comment'; v_pref := 'comments'; v_entity_type := new.entity_type; v_title := 'Новый комментарий'; v_entity := new.entity_id;
  else return new; end if;
  select display_name into v_actor_name from public.family_members where family_id = v_family and user_id = v_actor and removed_at is null;
  insert into public.notifications(family_id,user_id,kind,title,body,entity_type,entity_id)
  select v_family, fm.user_id, v_kind, v_title, coalesce(v_actor_name,'Участник') || ' добавил обновление.', v_entity_type, v_entity
  from public.family_members fm join public.profiles p on p.id = fm.user_id
  where fm.family_id = v_family and fm.removed_at is null and fm.user_id <> coalesce(v_actor,'00000000-0000-0000-0000-000000000000')
    and coalesce((p.notification_settings ->> v_pref)::boolean, true);
  return new;
end; $$;

-- Protect immutable identity and timestamps for families, memberships and templates.
create or replace function public.protect_family_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'Идентификатор, автор и время создания семьи защищены';
  end if;
  return new;
end; $$;
drop trigger if exists families_protect_identity on public.families;
create trigger families_protect_identity before update on public.families for each row execute function public.protect_family_identity();

create or replace function public.protect_membership_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user = 'postgres' then return new; end if;
  if new.id is distinct from old.id or new.user_id is distinct from old.user_id or
     new.family_id is distinct from old.family_id or new.role is distinct from old.role or
     new.removed_at is distinct from old.removed_at or new.joined_at is distinct from old.joined_at or
     new.last_active_at is distinct from old.last_active_at then
    raise exception 'Идентификатор, роль, семья и временные метки участника защищены';
  end if;
  return new;
end; $$;

create or replace function public.protect_template_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is null or new.created_by <> auth.uid() or not public.is_active_family_member(new.family_id) then
      raise exception 'Шаблон может создать только участник семьи';
    end if;
    new.created_at := now();
  elsif new.id is distinct from old.id or new.family_id is distinct from old.family_id or
        new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'Автор, идентификатор и время шаблона защищены';
  end if;
  return new;
end; $$;
drop trigger if exists task_templates_protect_identity on public.task_templates;
create trigger task_templates_protect_identity before insert or update on public.task_templates
for each row execute function public.protect_template_identity();

create or replace function public.protect_note_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or new.created_by <> auth.uid() or new.updated_by <> auth.uid() or not public.is_active_family_member(new.family_id) then
    raise exception 'Заметку может создать только участник семьи';
  end if;
  new.created_at := now(); new.updated_at := now();
  return new;
end; $$;
drop trigger if exists notes_protect_insert on public.family_notes;
create trigger notes_protect_insert before insert on public.family_notes
for each row execute function public.protect_note_insert();

-- Read status is changed only by mark_notification_read(), which supplies server time.
revoke update on public.notifications from authenticated;

create or replace function public.set_shopping_archived(p_item_id uuid, p_archived boolean)
returns public.shopping_items language plpgsql security definer set search_path = '' as $$
declare v_item public.shopping_items%rowtype;
begin
  select * into v_item from public.shopping_items where id = p_item_id for update;
  if not found or not public.is_active_family_member(v_item.family_id) then raise exception 'Товар не найден'; end if;
  update public.shopping_items set archived_at = case when p_archived then now() else null end where id = p_item_id returning * into v_item;
  return v_item;
end; $$;
revoke all on function public.set_shopping_archived(uuid,boolean) from public;
grant execute on function public.set_shopping_archived(uuid,boolean) to authenticated;

-- Validate preference values at the database boundary.
do $$ begin
  alter table public.profiles add constraint profiles_notification_settings_boolean check (
    jsonb_typeof(notification_settings->'tasks') = 'boolean' and
    jsonb_typeof(notification_settings->'shopping') = 'boolean' and
    jsonb_typeof(notification_settings->'comments') = 'boolean' and
    jsonb_typeof(notification_settings->'events') = 'boolean'
  );
exception when duplicate_object then null; end $$;

-- Reject forged completion/purchase metadata on INSERT and validate category ownership.
create or replace function public.set_family_author_snapshot() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_color text; v_actor uuid;
begin
  v_actor := case when tg_table_name = 'item_comments' then auth.uid() else new.created_by end;
  select display_name, avatar_color into v_name, v_color from public.family_members
    where family_id = new.family_id and user_id = v_actor and removed_at is null;
  if v_name is null then raise exception 'Нет активного членства в семье'; end if;
  if tg_table_name = 'tasks' then
    if new.status <> 'new' or new.completed_by is not null or new.completed_at is not null then
      raise exception 'Новая задача не может иметь данные выполнения';
    end if;
    if new.category_id is not null and not exists(select 1 from public.task_categories c where c.id = new.category_id and c.family_id = new.family_id) then
      raise exception 'Категория должна принадлежать этой семье';
    end if;
    new.creator_name := v_name;
  elsif tg_table_name = 'shopping_items' then
    if new.bought_by is not null or new.buyer_name is not null or new.bought_at is not null then
      raise exception 'Данные покупки устанавливаются серверной функцией';
    end if;
    new.creator_name := v_name;
  elsif tg_table_name = 'calendar_events' then
    new.creator_name := v_name;
  elsif tg_table_name = 'item_comments' then
    new.author_id := auth.uid(); new.author_name := v_name; new.author_avatar_color := v_color; new.edited_at := null;
  end if;
  new.created_at := now();
  return new;
end; $$;

create or replace function public.protect_category_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user = 'postgres' then return new; end if;
  if tg_op = 'INSERT' then
    if auth.uid() is null or new.created_by <> auth.uid() or not public.is_family_owner(new.family_id) then
      raise exception 'Категорию может создать только владелец семьи';
    end if;
    new.is_default := false; new.created_at := now();
  elsif new.id is distinct from old.id or new.family_id is distinct from old.family_id or
        new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at or
        new.is_default is distinct from old.is_default then
    raise exception 'Идентификатор, автор и тип категории защищены';
  end if;
  return new;
end; $$;
drop trigger if exists task_categories_protect_identity on public.task_categories;
create trigger task_categories_protect_identity before insert or update on public.task_categories
for each row execute function public.protect_category_identity();

-- Ensure Realtime emits invalidations for all collaborative records (if publication is available).
do $$ declare t text; begin
  foreach t in array array['family_members','family_events','task_categories','tasks','task_completion_history','shopping_items','item_comments','comment_reactions','calendar_events','notifications','family_notes','task_templates'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; when undefined_object then null; when insufficient_privilege then null; end;
  end loop;
end $$;
