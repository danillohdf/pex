-- =====================================================================
-- Plataforma PEX · estrutura do banco no Supabase
-- Rode este arquivo inteiro uma vez no SQL Editor do projeto
-- (Supabase › SQL Editor › New query › colar › Run).
-- Pode rodar de novo sem perder dados: tudo usa "if not exists"/"or replace".
-- =====================================================================

-- ---------- Perfis de acesso ----------
-- papel: pendente (acabou de se cadastrar) · auditor · admin · bloqueado
create table if not exists public.pex_perfis (
  id         uuid primary key references auth.users(id) on delete cascade,
  nome       text not null default '',
  email      text not null default '',
  papel      text not null default 'pendente' check (papel in ('pendente','auditor','admin','bloqueado')),
  criado_em  timestamptz not null default now()
);

-- Papel de quem está logado (security definer para não cair em recursão de RLS)
create or replace function public.pex_papel() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select papel from public.pex_perfis where id = auth.uid()), 'nenhum')
$$;

create or replace function public.pex_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select public.pex_papel() in ('auditor','admin')
$$;

create or replace function public.pex_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.pex_papel() = 'admin'
$$;

-- Cria o perfil quando alguém se cadastra. O primeiro cadastro vira administrador.
create or replace function public.pex_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.pex_perfis (id, nome, email, papel)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
    coalesce(new.email, ''),
    case when exists (select 1 from public.pex_perfis where papel = 'admin') then 'pendente' else 'admin' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists pex_on_auth_user_created on auth.users;
create trigger pex_on_auth_user_created
  after insert on auth.users
  for each row execute function public.pex_novo_usuario();

-- ---------- Dados do programa ----------
-- Cada registro guarda o documento inteiro em "data" (jsonb), no mesmo formato do protótipo.
create table if not exists public.pex_eventos (
  id             text primary key,
  data           jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now()
);

create table if not exists public.pex_visitas (
  id             text primary key,
  auditor        uuid not null default auth.uid() references auth.users(id),
  data           jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now()
);
create index if not exists pex_visitas_auditor_idx on public.pex_visitas(auditor);

create table if not exists public.pex_validacoes (
  id             text primary key references public.pex_visitas(id) on delete cascade,
  data           jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now()
);

create or replace function public.pex_touch() returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;

drop trigger if exists pex_eventos_touch on public.pex_eventos;
create trigger pex_eventos_touch before update on public.pex_eventos for each row execute function public.pex_touch();
drop trigger if exists pex_visitas_touch on public.pex_visitas;
create trigger pex_visitas_touch before update on public.pex_visitas for each row execute function public.pex_touch();
drop trigger if exists pex_validacoes_touch on public.pex_validacoes;
create trigger pex_validacoes_touch before update on public.pex_validacoes for each row execute function public.pex_touch();

-- A visita só pode ser alterada pelo próprio auditor enquanto é rascunho,
-- ou depois que a administração a devolveu (e antes de ele reenviar).
create or replace function public.pex_visita_editavel(v public.pex_visitas) returns boolean
language sql stable security definer set search_path = public as $$
  select v.auditor = auth.uid() and (
    (v.data->>'enviadoEm') is null
    or exists (
      select 1 from public.pex_validacoes w
      where w.id = v.id
        and w.data->>'status' = 'devolvida'
        and coalesce((v.data->>'enviadoEm')::numeric, 0) <= coalesce((w.data->>'em')::numeric, 0)
    )
  )
$$;

-- O auditor de uma visita nunca muda e precisa bater com o que está no documento.
create or replace function public.pex_visita_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.auditor := old.auditor;
  end if;
  new.data := jsonb_set(new.data, '{auditor}', to_jsonb(new.auditor::text));
  return new;
end $$;
drop trigger if exists pex_visitas_guard on public.pex_visitas;
create trigger pex_visitas_guard before insert or update on public.pex_visitas for each row execute function public.pex_visita_guard();

-- ---------- Segurança (RLS) ----------
alter table public.pex_perfis     enable row level security;
alter table public.pex_eventos    enable row level security;
alter table public.pex_visitas    enable row level security;
alter table public.pex_validacoes enable row level security;

drop policy if exists "perfis: ver" on public.pex_perfis;
create policy "perfis: ver" on public.pex_perfis for select to authenticated
  using (id = auth.uid() or public.pex_ativo());
drop policy if exists "perfis: admin altera" on public.pex_perfis;
create policy "perfis: admin altera" on public.pex_perfis for update to authenticated
  using (public.pex_admin()) with check (public.pex_admin());

drop policy if exists "eventos: ver" on public.pex_eventos;
create policy "eventos: ver" on public.pex_eventos for select to authenticated using (public.pex_ativo());
drop policy if exists "eventos: admin cria" on public.pex_eventos;
create policy "eventos: admin cria" on public.pex_eventos for insert to authenticated with check (public.pex_admin());
drop policy if exists "eventos: admin altera" on public.pex_eventos;
create policy "eventos: admin altera" on public.pex_eventos for update to authenticated using (public.pex_admin()) with check (public.pex_admin());
drop policy if exists "eventos: admin apaga" on public.pex_eventos;
create policy "eventos: admin apaga" on public.pex_eventos for delete to authenticated using (public.pex_admin());

drop policy if exists "visitas: ver" on public.pex_visitas;
create policy "visitas: ver" on public.pex_visitas for select to authenticated using (public.pex_ativo());
drop policy if exists "visitas: auditor cria" on public.pex_visitas;
create policy "visitas: auditor cria" on public.pex_visitas for insert to authenticated
  with check (public.pex_ativo() and auditor = auth.uid() and (data->>'enviadoEm') is null);
drop policy if exists "visitas: auditor edita" on public.pex_visitas;
create policy "visitas: auditor edita" on public.pex_visitas for update to authenticated
  using (public.pex_ativo() and public.pex_visita_editavel(pex_visitas))
  with check (auditor = auth.uid());
drop policy if exists "visitas: admin apaga" on public.pex_visitas;
create policy "visitas: admin apaga" on public.pex_visitas for delete to authenticated using (public.pex_admin());

drop policy if exists "validacoes: ver" on public.pex_validacoes;
create policy "validacoes: ver" on public.pex_validacoes for select to authenticated using (public.pex_ativo());
drop policy if exists "validacoes: admin cria" on public.pex_validacoes;
create policy "validacoes: admin cria" on public.pex_validacoes for insert to authenticated with check (public.pex_admin());
drop policy if exists "validacoes: admin altera" on public.pex_validacoes;
create policy "validacoes: admin altera" on public.pex_validacoes for update to authenticated using (public.pex_admin()) with check (public.pex_admin());

grant select, update on public.pex_perfis to authenticated;
grant select, insert, update, delete on public.pex_eventos, public.pex_visitas, public.pex_validacoes to authenticated;

-- ---------- Fotos (Storage) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pex-fotos', 'pex-fotos', false, 20971520, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "pex fotos: ver" on storage.objects;
create policy "pex fotos: ver" on storage.objects for select to authenticated
  using (bucket_id = 'pex-fotos' and public.pex_ativo());
drop policy if exists "pex fotos: enviar" on storage.objects;
create policy "pex fotos: enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'pex-fotos' and public.pex_ativo() and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "pex fotos: admin apaga" on storage.objects;
create policy "pex fotos: admin apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'pex-fotos' and public.pex_admin());

-- ---------- Tempo real ----------
do $$
declare t text;
begin
  foreach t in array array['pex_perfis','pex_eventos','pex_visitas','pex_validacoes'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- Endurecimento (avisos do Supabase Security Advisor) ----------
alter function public.pex_touch() set search_path = public;
alter function public.pex_visita_guard() set search_path = public;
revoke execute on function public.pex_papel(), public.pex_ativo(), public.pex_admin(), public.pex_novo_usuario(), public.pex_visita_editavel(public.pex_visitas), public.pex_touch(), public.pex_visita_guard() from public, anon;
revoke execute on function public.pex_novo_usuario() from authenticated;
-- Estas quatro precisam ficar liberadas para usuários logados: as regras de RLS as usam.
grant execute on function public.pex_papel(), public.pex_ativo(), public.pex_admin(), public.pex_visita_editavel(public.pex_visitas) to authenticated;
