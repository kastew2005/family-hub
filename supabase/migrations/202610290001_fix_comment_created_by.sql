-- Fix item_comments INSERT: never access NEW.created_by on tables that do not have that column.
-- Safe to run after all existing Family Hub migrations; does not modify family data.

create or replace function public.set_family_author_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_color text;
  v_actor uuid;
begin
  if tg_table_name = 'item_comments' then
    v_actor := auth.uid();
  else
    v_actor := new.created_by;
  end if;

  select display_name, avatar_color
    into v_name, v_color
  from public.family_members
  where family_id = new.family_id
    and user_id = v_actor
    and removed_at is null;

  if v_name is null then
    raise exception 'Нет активного членства в семье';
  end if;

  if tg_table_name = 'tasks' then
    if new.status <> 'new' or new.completed_by is not null or new.completed_at is not null then
      raise exception 'Новая задача не может иметь данные выполнения';
    end if;
    if new.category_id is not null and not exists (
      select 1 from public.task_categories c
      where c.id = new.category_id and c.family_id = new.family_id
    ) then
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
    new.author_id := auth.uid();
    new.author_name := v_name;
    new.author_avatar_color := v_color;
    new.edited_at := null;
  end if;

  new.created_at := now();
  return new;
end;
$$;

-- Keep server-owned field checks scoped to tables that actually have those fields.
create or replace function public.protect_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'postgres' then
    if tg_table_name = 'tasks' then
      if new.id is distinct from old.id
        or new.family_id is distinct from old.family_id
        or new.created_by is distinct from old.created_by
        or new.creator_name is distinct from old.creator_name
        or new.created_at is distinct from old.created_at
        or new.completed_by is distinct from old.completed_by
        or new.completed_at is distinct from old.completed_at
        or (
          new.status is distinct from old.status
          and (old.status = 'completed' or new.status = 'completed')
        )
      then
        raise exception 'Автор, идентификатор, семья и данные выполнения защищены';
      end if;
    elsif tg_table_name = 'shopping_items' then
      if new.id is distinct from old.id
        or new.family_id is distinct from old.family_id
        or new.created_by is distinct from old.created_by
        or new.creator_name is distinct from old.creator_name
        or new.created_at is distinct from old.created_at
        or new.bought_by is distinct from old.bought_by
        or new.buyer_name is distinct from old.buyer_name
        or new.bought_at is distinct from old.bought_at
      then
        raise exception 'Автор, идентификатор, семья и данные покупки защищены';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- Reaffirm the intended trigger attachment: the server-field guard belongs only on tasks and shopping.
drop trigger if exists tasks_protect_fields on public.tasks;
create trigger tasks_protect_fields
before update on public.tasks
for each row execute function public.protect_server_fields();

drop trigger if exists shopping_protect_fields on public.shopping_items;
create trigger shopping_protect_fields
before update on public.shopping_items
for each row execute function public.protect_server_fields();

-- Ensure comments use the comment-specific integrity guard, not the server-field guard.
drop trigger if exists comments_integrity on public.item_comments;
create trigger comments_integrity
before insert or update on public.item_comments
for each row execute function public.protect_comment_integrity();

drop trigger if exists comments_author_snapshot on public.item_comments;
create trigger comments_author_snapshot
before insert on public.item_comments
for each row execute function public.set_family_author_snapshot();
