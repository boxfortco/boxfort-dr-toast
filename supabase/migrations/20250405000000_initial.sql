-- BoxFort: Dr. Toast's Mix-Up — initial schema
-- Run via Supabase CLI (`supabase db push`) or paste into SQL Editor.

create extension if not exists "pgcrypto";

-- Game lifecycle (expand as you add phases)
create type public.game_state as enum (
  'lobby',
  'deal',
  'prompt',
  'voting',
  'resolution'
);

create table public.games (
  id uuid primary key default gen_random_uuid(),
  room_code text not null
    constraint room_code_format check (
      char_length(room_code) = 4
      and room_code = upper(room_code)
      and room_code ~ '^[A-Z]{4}$'
    ),
  state public.game_state not null default 'lobby',
  current_prompt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index games_room_code_key on public.games (room_code);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  display_name text not null,
  role text check (role is null or role in ('crew', 'imposter')),
  secret_word text,
  score integer not null default 0,
  created_at timestamptz not null default now()
);

create index players_game_id_idx on public.players (game_id);

-- Static content bank (prompts + word pairs) — host reads these when dealing
create table public.word_pairs (
  id uuid primary key default gen_random_uuid(),
  word_a text not null,
  word_b text not null,
  created_at timestamptz not null default now()
);

create table public.prompts (
  id uuid primary key default gen_random_uuid(),
  body text not null,
  created_at timestamptz not null default now()
);

-- Seed a couple of rows for local testing (optional)
insert into public.word_pairs (word_a, word_b) values
  ('Snowman', 'Sandcastle'),
  ('Birthday cake', 'Campfire');

insert into public.prompts (body) values
  ('I spent three hours building my [SECRET WORD], but then it was ruined by...');

-- Realtime: broadcast row changes to subscribed clients
alter publication supabase_realtime add table public.games;
alter publication supabase_realtime add table public.players;

-- updated_at helper
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger games_set_updated_at
  before update on public.games
  for each row execute function public.set_updated_at();

-- Row Level Security (MVP: open anon read/write for family party sessions)
-- Tighten before shipping: host tokens, Edge Functions, or signed room claims.
alter table public.games enable row level security;
alter table public.players enable row level security;
alter table public.word_pairs enable row level security;
alter table public.prompts enable row level security;

create policy "games_select_anon" on public.games for select to anon using (true);
create policy "games_insert_anon" on public.games for insert to anon with check (true);
create policy "games_update_anon" on public.games for update to anon using (true) with check (true);

create policy "players_select_anon" on public.players for select to anon using (true);
create policy "players_insert_anon" on public.players for insert to anon with check (true);
create policy "players_update_anon" on public.players for update to anon using (true) with check (true);

create policy "word_pairs_select_anon" on public.word_pairs for select to anon using (true);
create policy "prompts_select_anon" on public.prompts for select to anon using (true);
