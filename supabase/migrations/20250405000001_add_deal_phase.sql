-- Add explicit phase label for AI deal (distinct from legacy 'deal' if you use both)
do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'game_state'
      and e.enumlabel = 'deal_phase'
  ) then
    alter type public.game_state add value 'deal_phase';
  end if;
end
$$;
