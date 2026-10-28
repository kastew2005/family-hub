-- Family Hub part 2: tasks, shopping, comments, calendar, notifications and audit.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.task_categories (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 name text not null check (char_length(trim(name)) between 1 and 60), is_default boolean not null default false,
 sort_order integer not null default 100, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(family_id, name), unique(family_id, id)
);
create table if not exists public.tasks (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 160), description text not null default '',
 category_id uuid references public.task_categories(id) on delete set null, category_name text not null default 'Другое',
 created_by uuid not null references auth.users(id), creator_name text not null,
 assignee_id uuid references auth.users(id) on delete set null, due_at timestamptz,
 priority text not null default 'normal' check(priority in ('normal','important','urgent')),
 status text not null default 'new' check(status in ('new','in_progress','completed','cancelled')),
 completed_by uuid references auth.users(id) on delete set null, completed_at timestamptz,
 recurrence jsonb not null default '{"type":"none"}'::jsonb, recurrence_root_id uuid references public.tasks(id) on delete set null,
 recurrence_key text, is_favorite boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 version integer not null default 1,
 check ((status = 'completed' and completed_at is not null) or status <> 'completed'),
 unique(family_id, recurrence_root_id, recurrence_key)
);
create index if not exists tasks_family_status_due_idx on public.tasks(family_id,status,due_at);
create index if not exists tasks_family_created_idx on public.tasks(family_id,created_at desc);
create table if not exists public.task_completion_history (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
 family_id uuid not null references public.families(id) on delete cascade, completed_by uuid not null references auth.users(id),
 completed_at timestamptz not null default now(), reopened_at timestamptz, reopened_by uuid references auth.users(id)
);
create table if not exists public.shopping_items (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 160), quantity numeric(10,2) not null default 1 check(quantity > 0),
 unit text not null default 'шт.', category text not null default 'Другое' check(category in ('Продукты','Напитки','Бытовая химия','Гигиена','Дом','Аптека','Для детей','Другое')),
 estimated_price numeric(10,2) check(estimated_price >= 0), store text not null default '', note text not null default '',
 created_by uuid not null references auth.users(id), creator_name text not null, created_at timestamptz not null default now(),
 bought_by uuid references auth.users(id), buyer_name text, bought_at timestamptz, archived_at timestamptz,
 is_pinned boolean not null default false, updated_at timestamptz not null default now(), version integer not null default 1,
 check ((bought_by is null and bought_at is null) or (bought_by is not null and bought_at is not null))
);
create index if not exists shopping_family_active_idx on public.shopping_items(family_id,bought_at,created_at desc) where archived_at is null;
create table if not exists public.item_comments (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 entity_type text not null check(entity_type in ('task','shopping','event')), entity_id uuid not null,
 author_id uuid not null references auth.users(id), author_name text not null, author_avatar_color text not null default '#777D61',
 body text not null check(char_length(trim(body)) between 1 and 2000), parent_id uuid references public.item_comments(id) on delete set null,
 edited_at timestamptz, created_at timestamptz not null default now()
);
create index if not exists comments_entity_idx on public.item_comments(family_id,entity_type,entity_id,created_at);
create table if not exists public.comment_reactions (
 id uuid primary key default gen_random_uuid(), comment_id uuid not null references public.item_comments(id) on delete cascade,
 family_id uuid not null references public.families(id) on delete cascade, user_id uuid not null references auth.users(id),
 reaction text not null check(reaction in ('heart','like','thanks','laugh')), created_at timestamptz not null default now(), unique(comment_id,user_id,reaction)
);
create table if not exists public.calendar_events (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 160), description text not null default '',
 event_type text not null default 'family' check(event_type in ('birthday','meeting','chore','bill','family','other')),
 starts_at timestamptz not null, ends_at timestamptz, all_day boolean not null default false,
 created_by uuid not null references auth.users(id), creator_name text not null,
 recurrence jsonb not null default '{"type":"none"}'::jsonb, recurrence_root_id uuid references public.calendar_events(id) on delete set null,
 recurrence_key text, participant_ids uuid[] not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(family_id,recurrence_root_id,recurrence_key)
);
create index if not exists calendar_family_starts_idx on public.calendar_events(family_id,starts_at);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, kind text not null, title text not null, body text not null default '',
 entity_type text, entity_id uuid, read_at timestamptz, created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);
create table if not exists public.family_notes (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 title text not null default '', body text not null check(char_length(body) <= 10000), created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.task_templates (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
 title text not null, description text not null default '', category_name text not null default 'Другое', priority text not null default 'normal',
 recurrence jsonb not null default '{"type":"none"}'::jsonb, created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);

-- Common timestamps and optimistic version counters.
create or replace function public.touch_version() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at := now(); new.version := coalesce(old.version,0)+1; return new; end; $$;
drop trigger if exists tasks_touch_version on public.tasks; create trigger tasks_touch_version before update on public.tasks for each row execute function public.touch_version();
drop trigger if exists shopping_touch_version on public.shopping_items; create trigger shopping_touch_version before update on public.shopping_items for each row execute function public.touch_version();
drop trigger if exists calendar_touch_version on public.calendar_events; create trigger calendar_touch_version before update on public.calendar_events for each row execute function public.touch_version();
drop trigger if exists notes_touch_version on public.family_notes; create trigger notes_touch_version before update on public.family_notes for each row execute function public.set_updated_at();

-- Immutable server-owned completion/buyer metadata for direct client writes; dedicated RPCs own these fields.
create or replace function public.protect_server_fields() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user <> 'postgres' then
  if tg_table_name='tasks' and (new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or new.created_at is distinct from old.created_at or new.completed_by is distinct from old.completed_by or new.completed_at is distinct from old.completed_at) then raise exception 'Автор, семья и данные выполнения защищены сервером'; end if;
  if tg_table_name='shopping_items' and (new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or new.created_at is distinct from old.created_at or new.bought_by is distinct from old.bought_by or new.buyer_name is distinct from old.buyer_name or new.bought_at is distinct from old.bought_at) then raise exception 'Автор, семья и данные покупки защищены сервером'; end if;
 end if;
 return new;
end; $$;
drop trigger if exists tasks_protect_fields on public.tasks; create trigger tasks_protect_fields before update on public.tasks for each row execute function public.protect_server_fields();
drop trigger if exists shopping_protect_fields on public.shopping_items; create trigger shopping_protect_fields before update on public.shopping_items for each row execute function public.protect_server_fields();

create or replace function public.audit_family_change() returns trigger language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_actor uuid := auth.uid(); v_name text; v_type text; v_id uuid; v_details jsonb;
begin
 v_family := coalesce(new.family_id,old.family_id); v_id := coalesce(new.id,old.id);
 select fm.display_name into v_name from public.family_members fm where fm.family_id=v_family and fm.user_id=v_actor and fm.removed_at is null;
 if v_name is null then v_name := 'Участник'; end if;
 v_type := tg_table_name || '.' || lower(tg_op);
 if tg_op='INSERT' then v_details := jsonb_build_object('title',coalesce(to_jsonb(new)->>'title',to_jsonb(new)->>'name','')); elsif tg_op='DELETE' then v_details := jsonb_build_object('deleted',true); else v_details := jsonb_build_object('updated',true); end if;
 insert into public.family_events(family_id,actor_id,actor_name_snapshot,event_type,entity_type,entity_id,details) values(v_family,v_actor,v_name,v_type,tg_table_name,v_id,v_details);
 return coalesce(new,old);
end; $$;
-- Audit triggers intentionally only on core editable entities. Completion RPC writes a separate history row.
drop trigger if exists tasks_audit on public.tasks; create trigger tasks_audit after insert or update or delete on public.tasks for each row execute function public.audit_family_change();
drop trigger if exists shopping_audit on public.shopping_items; create trigger shopping_audit after insert or update or delete on public.shopping_items for each row execute function public.audit_family_change();
drop trigger if exists comments_audit on public.item_comments; create trigger comments_audit after insert or update or delete on public.item_comments for each row execute function public.audit_family_change();
drop trigger if exists calendar_audit on public.calendar_events; create trigger calendar_audit after insert or update or delete on public.calendar_events for each row execute function public.audit_family_change();

create or replace function public.complete_task(p_task_id uuid) returns public.tasks language plpgsql security definer set search_path='' as $$
declare v_task public.tasks%rowtype; v_name text;
begin
 select * into v_task from public.tasks where id=p_task_id for update;
 if not found or not public.is_active_family_member(v_task.family_id) then raise exception 'Задача не найдена'; end if;
 if v_task.status='cancelled' then raise exception 'Отменённую задачу нельзя выполнить'; end if;
 if v_task.assignee_id is not null and v_task.assignee_id<>auth.uid() and not public.is_family_owner(v_task.family_id) then raise exception 'Задача назначена другому участнику'; end if;
 select display_name into v_name from public.family_members where family_id=v_task.family_id and user_id=auth.uid() and removed_at is null;
 update public.tasks set status='completed',completed_by=auth.uid(),completed_at=now() where id=p_task_id returning * into v_task;
 insert into public.task_completion_history(task_id,family_id,completed_by,completed_at) values(v_task.id,v_task.family_id,auth.uid(),v_task.completed_at);
 return v_task;
end; $$;
create or replace function public.reopen_task(p_task_id uuid) returns public.tasks language plpgsql security definer set search_path='' as $$
declare v_task public.tasks%rowtype;
begin
 select * into v_task from public.tasks where id=p_task_id for update;
 if not found or not public.is_active_family_member(v_task.family_id) then raise exception 'Задача не найдена'; end if;
 if v_task.status<>'completed' then raise exception 'Задача не выполнена'; end if;
 update public.task_completion_history set reopened_at=now(),reopened_by=auth.uid() where id=(select id from public.task_completion_history where task_id=p_task_id and reopened_at is null order by completed_at desc limit 1);
 update public.tasks set status='in_progress',completed_by=null,completed_at=null where id=p_task_id returning * into v_task;
 return v_task;
end; $$;
create or replace function public.set_shopping_bought(p_item_id uuid,p_bought boolean) returns public.shopping_items language plpgsql security definer set search_path='' as $$
declare v_item public.shopping_items%rowtype; v_name text;
begin
 select * into v_item from public.shopping_items where id=p_item_id for update;
 if not found or not public.is_active_family_member(v_item.family_id) then raise exception 'Товар не найден'; end if;
 select display_name into v_name from public.family_members where family_id=v_item.family_id and user_id=auth.uid() and removed_at is null;
 if p_bought then update public.shopping_items set bought_by=auth.uid(),buyer_name=v_name,bought_at=now() where id=p_item_id;
 else update public.shopping_items set bought_by=null,buyer_name=null,bought_at=null where id=p_item_id; end if;
 return (select * from public.shopping_items where id=p_item_id);
end; $$;
revoke all on function public.complete_task(uuid) from public; grant execute on function public.complete_task(uuid) to authenticated;
revoke all on function public.reopen_task(uuid) from public; grant execute on function public.reopen_task(uuid) to authenticated;
revoke all on function public.set_shopping_bought(uuid,boolean) from public; grant execute on function public.set_shopping_bought(uuid,boolean) to authenticated;

-- RLS is applied to every family-scoped table. Access always derives from active membership.
do $$ declare t text; begin
 foreach t in array array['task_categories','tasks','task_completion_history','shopping_items','item_comments','comment_reactions','calendar_events','notifications','family_notes','task_templates'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

drop policy if exists categories_read on public.task_categories; create policy categories_read on public.task_categories for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists categories_insert on public.task_categories; create policy categories_insert on public.task_categories for insert to authenticated with check(public.is_family_owner(family_id) and created_by=auth.uid());
drop policy if exists categories_update on public.task_categories; create policy categories_update on public.task_categories for update to authenticated using(public.is_family_owner(family_id)) with check(public.is_family_owner(family_id));
drop policy if exists categories_delete on public.task_categories; create policy categories_delete on public.task_categories for delete to authenticated using(public.is_family_owner(family_id) and not is_default);

drop policy if exists tasks_read on public.tasks; create policy tasks_read on public.tasks for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists tasks_insert on public.tasks; create policy tasks_insert on public.tasks for insert to authenticated with check(public.is_active_family_member(family_id) and created_by=auth.uid());
drop policy if exists tasks_update on public.tasks; create policy tasks_update on public.tasks for update to authenticated using(public.is_active_family_member(family_id)) with check(public.is_active_family_member(family_id));
drop policy if exists tasks_delete on public.tasks; create policy tasks_delete on public.tasks for delete to authenticated using(public.is_active_family_member(family_id) and (created_by=auth.uid() or public.is_family_owner(family_id)));
drop policy if exists completion_read on public.task_completion_history; create policy completion_read on public.task_completion_history for select to authenticated using(public.is_active_family_member(family_id));

drop policy if exists shopping_read on public.shopping_items; create policy shopping_read on public.shopping_items for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists shopping_insert on public.shopping_items; create policy shopping_insert on public.shopping_items for insert to authenticated with check(public.is_active_family_member(family_id) and created_by=auth.uid());
drop policy if exists shopping_update on public.shopping_items; create policy shopping_update on public.shopping_items for update to authenticated using(public.is_active_family_member(family_id)) with check(public.is_active_family_member(family_id));
drop policy if exists shopping_delete on public.shopping_items; create policy shopping_delete on public.shopping_items for delete to authenticated using(public.is_active_family_member(family_id) and (created_by=auth.uid() or public.is_family_owner(family_id)));

drop policy if exists comments_read on public.item_comments; create policy comments_read on public.item_comments for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists comments_insert on public.item_comments; create policy comments_insert on public.item_comments for insert to authenticated with check(public.is_active_family_member(family_id) and author_id=auth.uid());
drop policy if exists comments_update_own on public.item_comments; create policy comments_update_own on public.item_comments for update to authenticated using(author_id=auth.uid() and public.is_active_family_member(family_id)) with check(author_id=auth.uid() and public.is_active_family_member(family_id));
drop policy if exists comments_delete_own on public.item_comments; create policy comments_delete_own on public.item_comments for delete to authenticated using((author_id=auth.uid() or public.is_family_owner(family_id)) and public.is_active_family_member(family_id));
drop policy if exists reactions_read on public.comment_reactions; create policy reactions_read on public.comment_reactions for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists reactions_insert on public.comment_reactions; create policy reactions_insert on public.comment_reactions for insert to authenticated with check(user_id=auth.uid() and public.is_active_family_member(family_id));
drop policy if exists reactions_delete on public.comment_reactions; create policy reactions_delete on public.comment_reactions for delete to authenticated using(user_id=auth.uid() and public.is_active_family_member(family_id));

drop policy if exists calendar_read on public.calendar_events; create policy calendar_read on public.calendar_events for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists calendar_insert on public.calendar_events; create policy calendar_insert on public.calendar_events for insert to authenticated with check(public.is_active_family_member(family_id) and created_by=auth.uid());
drop policy if exists calendar_update on public.calendar_events; create policy calendar_update on public.calendar_events for update to authenticated using(public.is_active_family_member(family_id)) with check(public.is_active_family_member(family_id));
drop policy if exists calendar_delete on public.calendar_events; create policy calendar_delete on public.calendar_events for delete to authenticated using(created_by=auth.uid() or public.is_family_owner(family_id));

drop policy if exists notifications_read_own on public.notifications; create policy notifications_read_own on public.notifications for select to authenticated using(user_id=auth.uid() and public.is_active_family_member(family_id));
drop policy if exists notifications_update_own on public.notifications; create policy notifications_update_own on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists notes_read on public.family_notes; create policy notes_read on public.family_notes for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists notes_insert on public.family_notes; create policy notes_insert on public.family_notes for insert to authenticated with check(public.is_active_family_member(family_id) and created_by=auth.uid() and updated_by=auth.uid());
drop policy if exists notes_update on public.family_notes; create policy notes_update on public.family_notes for update to authenticated using(public.is_active_family_member(family_id)) with check(public.is_active_family_member(family_id) and updated_by=auth.uid());
drop policy if exists notes_delete on public.family_notes; create policy notes_delete on public.family_notes for delete to authenticated using(created_by=auth.uid() or public.is_family_owner(family_id));
drop policy if exists templates_read on public.task_templates; create policy templates_read on public.task_templates for select to authenticated using(public.is_active_family_member(family_id));
drop policy if exists templates_insert on public.task_templates; create policy templates_insert on public.task_templates for insert to authenticated with check(public.is_active_family_member(family_id) and created_by=auth.uid());
drop policy if exists templates_delete on public.task_templates; create policy templates_delete on public.task_templates for delete to authenticated using(created_by=auth.uid() or public.is_family_owner(family_id));

grant select,insert,update,delete on public.task_categories,public.tasks,public.shopping_items,public.item_comments,public.comment_reactions,public.calendar_events,public.family_notes,public.task_templates to authenticated;
grant select on public.task_completion_history to authenticated;
grant select,update on public.notifications to authenticated;
grant select,insert,update,delete on public.task_categories,public.tasks,public.shopping_items,public.item_comments,public.comment_reactions,public.calendar_events,public.family_notes,public.task_templates to authenticated;

do $$ declare t text; begin
 foreach t in array array['task_categories','tasks','shopping_items','item_comments','calendar_events','notifications'] loop
  begin execute format('alter publication supabase_realtime add table public.%I',t);
  exception when duplicate_object then null; when undefined_object then null; end;
 end loop;
end $$;

-- Fill author snapshots from membership, never trust client-supplied display names.
create or replace function public.set_family_author_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
declare v_name text; v_color text; v_actor uuid;
begin
 v_actor:=case when tg_table_name='item_comments' then auth.uid() else new.created_by end;
 select display_name,avatar_color into v_name,v_color from public.family_members where family_id=new.family_id and user_id=v_actor and removed_at is null;
 if v_name is null then raise exception 'Нет активного членства в семье'; end if;
 if tg_table_name='tasks' or tg_table_name='shopping_items' or tg_table_name='calendar_events' then
  if tg_table_name='tasks' then new.creator_name:=v_name; elsif tg_table_name='shopping_items' then new.creator_name:=v_name; else new.creator_name:=v_name; end if;
 elsif tg_table_name='item_comments' then new.author_id:=auth.uid(); new.author_name:=v_name; new.author_avatar_color:=v_color;
 end if;
 return new;
end; $$;
drop trigger if exists tasks_author_snapshot on public.tasks; create trigger tasks_author_snapshot before insert on public.tasks for each row execute function public.set_family_author_snapshot();
drop trigger if exists shopping_author_snapshot on public.shopping_items; create trigger shopping_author_snapshot before insert on public.shopping_items for each row execute function public.set_family_author_snapshot();
drop trigger if exists calendar_author_snapshot on public.calendar_events; create trigger calendar_author_snapshot before insert on public.calendar_events for each row execute function public.set_family_author_snapshot();
drop trigger if exists comments_author_snapshot on public.item_comments; create trigger comments_author_snapshot before insert on public.item_comments for each row execute function public.set_family_author_snapshot();

-- In-app notifications are stored per recipient; no Web Push is claimed or attempted.
create or replace function public.notify_family_members() returns trigger language plpgsql security definer set search_path='' as $$
declare v_actor uuid := auth.uid(); v_title text; v_family uuid; v_entity uuid; v_kind text; v_actor_name text;
begin
 v_family:=new.family_id; v_entity:=new.id;
 if tg_table_name='tasks' then v_kind:='task'; v_title:='Новая задача: '||new.title;
 elsif tg_table_name='shopping_items' then v_kind:='shopping'; v_title:='Добавлен товар: '||new.title;
 elsif tg_table_name='item_comments' then v_kind:='comment'; v_title:='Новый комментарий';
 else return new; end if;
 select display_name into v_actor_name from public.family_members where family_id=v_family and user_id=v_actor and removed_at is null;
 insert into public.notifications(family_id,user_id,kind,title,body,entity_type,entity_id)
 select v_family,fm.user_id,v_kind,v_title,coalesce(v_actor_name,'Участник')||' добавил обновление.',case when tg_table_name='item_comments' then new.entity_type else tg_table_name end,case when tg_table_name='item_comments' then new.entity_id else v_entity end
 from public.family_members fm where fm.family_id=v_family and fm.removed_at is null and fm.user_id<>coalesce(v_actor,'00000000-0000-0000-0000-000000000000');
 return new;
end; $$;
drop trigger if exists tasks_notify on public.tasks; create trigger tasks_notify after insert on public.tasks for each row execute function public.notify_family_members();
drop trigger if exists shopping_notify on public.shopping_items; create trigger shopping_notify after insert on public.shopping_items for each row execute function public.notify_family_members();
drop trigger if exists comments_notify on public.item_comments; create trigger comments_notify after insert on public.item_comments for each row execute function public.notify_family_members();

-- Generate the next task occurrence only when completing a recurring task. The unique key prevents duplicates.
create or replace function public.complete_task(p_task_id uuid) returns public.tasks language plpgsql security definer set search_path='' as $$
declare v_task public.tasks%rowtype; v_next_due timestamptz; v_root uuid; v_key text; v_name text;
begin
 select * into v_task from public.tasks where id=p_task_id for update;
 if not found or not public.is_active_family_member(v_task.family_id) then raise exception 'Задача не найдена'; end if;
 if v_task.status='cancelled' then raise exception 'Отменённую задачу нельзя выполнить'; end if;
 if v_task.assignee_id is not null and v_task.assignee_id<>auth.uid() and not public.is_family_owner(v_task.family_id) then raise exception 'Задача назначена другому участнику'; end if;
 update public.tasks set status='completed',completed_by=auth.uid(),completed_at=now() where id=p_task_id returning * into v_task;
 insert into public.task_completion_history(task_id,family_id,completed_by,completed_at) values(v_task.id,v_task.family_id,auth.uid(),v_task.completed_at);
 if v_task.due_at is not null then
  case v_task.recurrence->>'type'
   when 'daily' then v_next_due:=v_task.due_at+interval '1 day';
   when 'weekly' then v_next_due:=v_task.due_at+interval '7 days';
   when 'monthly' then v_next_due:=v_task.due_at+interval '1 month';
   else v_next_due:=null;
  end case;
  if v_next_due is not null then
   v_root:=coalesce(v_task.recurrence_root_id,v_task.id); v_key:=to_char(v_next_due at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS');
   insert into public.tasks(family_id,title,description,category_id,category_name,created_by,creator_name,assignee_id,due_at,priority,status,recurrence,recurrence_root_id,recurrence_key)
   values(v_task.family_id,v_task.title,v_task.description,v_task.category_id,v_task.category_name,v_task.created_by,v_task.creator_name,v_task.assignee_id,v_next_due,v_task.priority,'new',v_task.recurrence,v_root,v_key)
   on conflict(family_id,recurrence_root_id,recurrence_key) do nothing;
  end if;
 end if;
 return v_task;
end; $$;
revoke all on function public.complete_task(uuid) from public; grant execute on function public.complete_task(uuid) to authenticated;

-- Notifications are user-owned; clients may only mark them read.
revoke update on public.notifications from authenticated; grant update(read_at) on public.notifications to authenticated;

-- Seed the eight built-in categories for new and existing families.
create or replace function public.seed_family_categories() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.task_categories(family_id,name,is_default,sort_order,created_by) values
 (new.id,'Список покупок',true,10,new.created_by),(new.id,'Уборка и порядок',true,20,new.created_by),
 (new.id,'Домашние обязанности',true,30,new.created_by),(new.id,'Поручения',true,40,new.created_by),
 (new.id,'Ремонт и обслуживание',true,50,new.created_by),(new.id,'Семейные дела',true,60,new.created_by),
 (new.id,'Учёба и работа',true,70,new.created_by),(new.id,'Другое',true,80,new.created_by)
 on conflict(family_id,name) do nothing;
 return new;
end; $$;
drop trigger if exists families_seed_categories on public.families;
create trigger families_seed_categories after insert on public.families for each row execute function public.seed_family_categories();
insert into public.task_categories(family_id,name,is_default,sort_order,created_by)
select f.id,v.name,true,v.sort_order,f.created_by from public.families f cross join (values
 ('Список покупок',10),('Уборка и порядок',20),('Домашние обязанности',30),('Поручения',40),('Ремонт и обслуживание',50),('Семейные дела',60),('Учёба и работа',70),('Другое',80)
) as v(name,sort_order) on conflict(family_id,name) do nothing;

-- Validate comment targets and protect author/target/time metadata on edits.
create or replace function public.protect_comment_integrity() returns trigger language plpgsql security definer set search_path='' as $$
declare v_family uuid;
begin
 if tg_op='UPDATE' then
  if new.family_id is distinct from old.family_id or new.entity_type is distinct from old.entity_type or new.entity_id is distinct from old.entity_id or new.author_id is distinct from old.author_id or new.author_name is distinct from old.author_name or new.author_avatar_color is distinct from old.author_avatar_color or new.created_at is distinct from old.created_at then raise exception 'Автор и контекст комментария защищены'; end if;
  new.edited_at:=now();
 end if;
 if tg_op='INSERT' then
  if new.entity_type='task' then select family_id into v_family from public.tasks where id=new.entity_id;
  elsif new.entity_type='shopping' then select family_id into v_family from public.shopping_items where id=new.entity_id;
  else select family_id into v_family from public.calendar_events where id=new.entity_id; end if;
  if v_family is null or v_family<>new.family_id then raise exception 'Объект обсуждения не найден в этой семье'; end if;
  if new.parent_id is not null and not exists(select 1 from public.item_comments p where p.id=new.parent_id and p.family_id=new.family_id and p.entity_type=new.entity_type and p.entity_id=new.entity_id) then raise exception 'Ответ должен относиться к этому обсуждению'; end if;
 end if;
 return new;
end; $$;
drop trigger if exists comments_integrity on public.item_comments; create trigger comments_integrity before insert or update on public.item_comments for each row execute function public.protect_comment_integrity();

create or replace function public.protect_calendar_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user<>'postgres' and (new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or new.created_at is distinct from old.created_at) then raise exception 'Автор и время создания события защищены'; end if;
 return new;
end; $$;
drop trigger if exists calendar_protect_identity on public.calendar_events; create trigger calendar_protect_identity before update on public.calendar_events for each row execute function public.protect_calendar_identity();

-- Keep comment threads consistent when their source item is deleted.
create or replace function public.delete_entity_comments() returns trigger language plpgsql security definer set search_path='' as $$
declare v_type text;
begin
 v_type:=case when tg_table_name='tasks' then 'task' when tg_table_name='shopping_items' then 'shopping' else 'event' end;
 delete from public.item_comments where family_id=old.family_id and entity_type=v_type and entity_id=old.id;
 return old;
end; $$;
drop trigger if exists tasks_delete_comments on public.tasks; create trigger tasks_delete_comments after delete on public.tasks for each row execute function public.delete_entity_comments();
drop trigger if exists shopping_delete_comments on public.shopping_items; create trigger shopping_delete_comments after delete on public.shopping_items for each row execute function public.delete_entity_comments();
drop trigger if exists events_delete_comments on public.calendar_events; create trigger events_delete_comments after delete on public.calendar_events for each row execute function public.delete_entity_comments();

-- Normalize notification destinations to singular client route names.
create or replace function public.notify_family_members() returns trigger language plpgsql security definer set search_path='' as $$
declare v_actor uuid := auth.uid(); v_title text; v_family uuid; v_entity uuid; v_kind text; v_actor_name text; v_entity_type text; v_target uuid;
begin
 v_family:=new.family_id; v_entity:=new.id;
 if tg_table_name='tasks' then v_kind:='task'; v_entity_type:='task'; v_title:='Новая задача: '||new.title; v_target:=v_entity;
 elsif tg_table_name='shopping_items' then v_kind:='shopping'; v_entity_type:='shopping'; v_title:='Добавлен товар: '||new.title; v_target:=v_entity;
 elsif tg_table_name='item_comments' then v_kind:='comment'; v_entity_type:=new.entity_type; v_title:='Новый комментарий'; v_target:=new.entity_id;
 else return new; end if;
 select display_name into v_actor_name from public.family_members where family_id=v_family and user_id=v_actor and removed_at is null;
 insert into public.notifications(family_id,user_id,kind,title,body,entity_type,entity_id)
 select v_family,fm.user_id,v_kind,v_title,coalesce(v_actor_name,'Участник')||' добавил обновление.',v_entity_type,v_target
 from public.family_members fm where fm.family_id=v_family and fm.removed_at is null and fm.user_id<>coalesce(v_actor,'00000000-0000-0000-0000-000000000000');
 return new;
end; $$;

-- Server timestamps on user-created rows cannot be backdated by clients.
create or replace function public.set_family_author_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
declare v_name text; v_color text; v_actor uuid;
begin
 v_actor:=case when tg_table_name='item_comments' then auth.uid() else new.created_by end;
 select display_name,avatar_color into v_name,v_color from public.family_members where family_id=new.family_id and user_id=v_actor and removed_at is null;
 if v_name is null then raise exception 'Нет активного членства в семье'; end if;
 new.created_at:=now();
 if tg_table_name='tasks' then new.creator_name:=v_name;
 elsif tg_table_name='shopping_items' then new.creator_name:=v_name;
 elsif tg_table_name='calendar_events' then new.creator_name:=v_name;
 elsif tg_table_name='item_comments' then new.author_id:=auth.uid(); new.author_name:=v_name; new.author_avatar_color:=v_color;
 end if;
 return new;
end; $$;

create or replace function public.mark_notification_read(p_notification_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.notifications set read_at=now() where id=p_notification_id and user_id=auth.uid() and public.is_active_family_member(family_id);
 if not found then raise exception 'Уведомление не найдено'; end if;
end; $$;
revoke all on function public.mark_notification_read(uuid) from public; grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.notify_family_members() returns trigger language plpgsql security definer set search_path='' as $$
declare v_actor uuid := auth.uid(); v_title text; v_family uuid; v_entity uuid; v_kind text; v_actor_name text; v_entity_type text; v_target uuid;
begin
 v_family:=new.family_id; v_entity:=new.id;
 if tg_table_name='tasks' then
  if tg_op='UPDATE' and old.status is not distinct from new.status then return new; end if;
  v_kind:='task'; v_entity_type:='task'; v_target:=v_entity;
  v_title:=case when new.status='completed' then 'Задача выполнена: '||new.title when tg_op='UPDATE' then 'Задача обновлена: '||new.title else 'Новая задача: '||new.title end;
 elsif tg_table_name='shopping_items' then
  if tg_op='UPDATE' and old.bought_at is not distinct from new.bought_at then return new; end if;
  v_kind:='shopping'; v_entity_type:='shopping'; v_target:=v_entity;
  v_title:=case when new.bought_at is not null then 'Товар куплен: '||new.title else 'Товар возвращён в список: '||new.title end;
 elsif tg_table_name='calendar_events' then
  if new.recurrence_root_id is not null then return new; end if;
  v_kind:='event'; v_entity_type:='event'; v_target:=v_entity; v_title:='Семейное событие: '||new.title;
 elsif tg_table_name='item_comments' then
  v_kind:='comment'; v_entity_type:=new.entity_type; v_title:='Новый комментарий'; v_target:=new.entity_id;
 else return new; end if;
 select display_name into v_actor_name from public.family_members where family_id=v_family and user_id=v_actor and removed_at is null;
 insert into public.notifications(family_id,user_id,kind,title,body,entity_type,entity_id)
 select v_family,fm.user_id,v_kind,v_title,coalesce(v_actor_name,'Участник')||' добавил обновление.',v_entity_type,v_target
 from public.family_members fm where fm.family_id=v_family and fm.removed_at is null and fm.user_id<>coalesce(v_actor,'00000000-0000-0000-0000-000000000000');
 return new;
end; $$;
drop trigger if exists tasks_notify on public.tasks; create trigger tasks_notify after insert or update on public.tasks for each row execute function public.notify_family_members();
drop trigger if exists shopping_notify on public.shopping_items; create trigger shopping_notify after insert or update on public.shopping_items for each row execute function public.notify_family_members();

drop trigger if exists calendar_notify on public.calendar_events; create trigger calendar_notify after insert on public.calendar_events for each row execute function public.notify_family_members();

create or replace function public.protect_reaction_integrity() returns trigger language plpgsql security definer set search_path='' as $$
declare v_family uuid;
begin
 if tg_op='INSERT' then
  select family_id into v_family from public.item_comments where id=new.comment_id;
  if v_family is null or v_family<>new.family_id then raise exception 'Реакция должна относиться к комментарию этой семьи'; end if;
  if new.user_id<>auth.uid() then raise exception 'Нельзя добавлять реакцию от имени другого участника'; end if;
  new.created_at:=now();
 end if;
 return new;
end; $$;
drop trigger if exists reactions_integrity on public.comment_reactions; create trigger reactions_integrity before insert on public.comment_reactions for each row execute function public.protect_reaction_integrity();

create or replace function public.protect_note_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then raise exception 'Автор и время создания заметки защищены'; end if;
 new.updated_by:=auth.uid(); new.updated_at:=now(); return new;
end; $$;
drop trigger if exists notes_protect_identity on public.family_notes; create trigger notes_protect_identity before update on public.family_notes for each row execute function public.protect_note_identity();

-- Validate assignees and calendar participants against the same family.
create or replace function public.validate_family_assignments() returns trigger language plpgsql security definer set search_path='' as $$
declare v_member uuid;
begin
 if tg_table_name='tasks' then
  if new.assignee_id is not null and not exists(select 1 from public.family_members where family_id=new.family_id and user_id=new.assignee_id and removed_at is null) then raise exception 'Исполнитель должен быть участником этой семьи'; end if;
  if not exists(select 1 from public.task_categories where family_id=new.family_id and name=new.category_name) then raise exception 'Выберите существующую категорию задачи'; end if;
 elsif tg_table_name='calendar_events' then
  foreach v_member in array new.participant_ids loop
   if not exists(select 1 from public.family_members where family_id=new.family_id and user_id=v_member and removed_at is null) then raise exception 'Все участники события должны состоять в этой семье'; end if;
  end loop;
 end if;
 return new;
end; $$;
drop trigger if exists tasks_validate_assignment on public.tasks; create trigger tasks_validate_assignment before insert or update on public.tasks for each row execute function public.validate_family_assignments();
drop trigger if exists events_validate_participants on public.calendar_events; create trigger events_validate_participants before insert or update on public.calendar_events for each row execute function public.validate_family_assignments();

-- A completed task can only be reopened through the RPC that records its history.
create or replace function public.protect_server_fields() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user <> 'postgres' then
  if tg_table_name='tasks' and (new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or new.created_at is distinct from old.created_at or new.completed_by is distinct from old.completed_by or new.completed_at is distinct from old.completed_at or (new.status is distinct from old.status and (old.status='completed' or new.status='completed'))) then raise exception 'Автор, семья и данные выполнения защищены сервером'; end if;
  if tg_table_name='shopping_items' and (new.family_id is distinct from old.family_id or new.created_by is distinct from old.created_by or new.creator_name is distinct from old.creator_name or new.created_at is distinct from old.created_at or new.bought_by is distinct from old.bought_by or new.buyer_name is distinct from old.buyer_name or new.bought_at is distinct from old.bought_at) then raise exception 'Автор, семья и данные покупки защищены сервером'; end if;
 end if;
 return new;
end; $$;

-- Store useful before/after snapshots in the immutable family audit trail.
create or replace function public.audit_family_change() returns trigger language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_actor uuid := auth.uid(); v_name text; v_type text; v_id uuid; v_details jsonb; v_new jsonb; v_old jsonb; v_category text;
begin
 v_new:=case when tg_op='DELETE' then null else to_jsonb(new) end;
 v_old:=case when tg_op='INSERT' then null else to_jsonb(old) end;
 v_family:=coalesce(v_new->>'family_id',v_old->>'family_id')::uuid;
 v_id:=coalesce(v_new->>'id',v_old->>'id')::uuid;
 select fm.display_name into v_name from public.family_members fm where fm.family_id=v_family and fm.user_id=v_actor and fm.removed_at is null;
 if v_name is null then v_name:='Участник'; end if;
 v_type:=tg_table_name||'.'||lower(tg_op);
 v_category:=coalesce(v_new->>'category_name',v_new->>'category',v_new->>'event_type',v_old->>'category_name',v_old->>'category',v_old->>'event_type','');
 if tg_op='INSERT' then v_details:=jsonb_build_object('title',coalesce(v_new->>'title',v_new->>'name',''),'category',v_category);
 elsif tg_op='DELETE' then v_details:=jsonb_build_object('deleted',true,'title',coalesce(v_old->>'title',v_old->>'name',''),'category',v_category);
 else v_details:=jsonb_build_object('category',v_category,'before',jsonb_build_object('title',v_old->>'title','status',v_old->>'status','priority',v_old->>'priority','due_at',v_old->>'due_at','assignee_id',v_old->>'assignee_id','quantity',v_old->>'quantity','estimated_price',v_old->>'estimated_price','starts_at',v_old->>'starts_at'),'after',jsonb_build_object('title',v_new->>'title','status',v_new->>'status','priority',v_new->>'priority','due_at',v_new->>'due_at','assignee_id',v_new->>'assignee_id','quantity',v_new->>'quantity','estimated_price',v_new->>'estimated_price','starts_at',v_new->>'starts_at')); end if;
 insert into public.family_events(family_id,actor_id,actor_name_snapshot,event_type,entity_type,entity_id,details) values(v_family,v_actor,v_name,v_type,tg_table_name,v_id,v_details);
 return coalesce(new,old);
end; $$;
