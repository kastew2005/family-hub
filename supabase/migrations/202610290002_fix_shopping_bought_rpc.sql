-- Fix set_shopping_bought: a scalar subquery cannot return every column of a row.
-- Preserve the composite return type and all existing shopping data.

create or replace function public.set_shopping_bought(p_item_id uuid, p_bought boolean)
returns public.shopping_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.shopping_items%rowtype;
  v_name text;
begin
  select * into v_item
  from public.shopping_items
  where id = p_item_id
  for update;

  if not found or not public.is_active_family_member(v_item.family_id) then
    raise exception 'Товар не найден';
  end if;

  select display_name into v_name
  from public.family_members
  where family_id = v_item.family_id
    and user_id = auth.uid()
    and removed_at is null;

  if p_bought then
    update public.shopping_items
    set bought_by = auth.uid(), buyer_name = v_name, bought_at = now()
    where id = p_item_id
    returning * into v_item;
  else
    update public.shopping_items
    set bought_by = null, buyer_name = null, bought_at = null
    where id = p_item_id
    returning * into v_item;
  end if;

  return v_item;
end;
$$;

revoke all on function public.set_shopping_bought(uuid, boolean) from public;
grant execute on function public.set_shopping_bought(uuid, boolean) to authenticated;
