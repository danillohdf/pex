-- =====================================================================
-- PEX 2.0 · Fase 6 · Notificações internas
-- Só acrescenta estruturas. Geradas pelo banco (gatilhos), lidas pelo app.
-- Preparado para e-mail/WhatsApp: colunas canais e enviado_*_em (não usadas ainda).
-- =====================================================================
create table if not exists public.pex_notificacoes (
  id          bigint generated always as identity primary key,
  usuario     uuid not null references auth.users(id) on delete cascade,
  tipo        text not null,
  titulo      text not null,
  texto       text not null default '',
  alvo_tipo   text check (alvo_tipo in ('visita','acao')),
  alvo_id     text,
  chave       text,
  criada_em   timestamptz not null default now(),
  lida_em     timestamptz,
  canais      jsonb not null default '{"app": true}'::jsonb,
  enviado_email_em    timestamptz,
  enviado_whatsapp_em timestamptz,
  unique (usuario, chave)
);
create index if not exists pex_notif_usuario_idx on public.pex_notificacoes(usuario, criada_em desc);

alter table public.pex_notificacoes enable row level security;
drop policy if exists "notif: dono ve" on public.pex_notificacoes;
create policy "notif: dono ve" on public.pex_notificacoes for select to authenticated using (usuario = auth.uid());
grant select on public.pex_notificacoes to authenticated;

-- envia para todos os administradores (admin e master), menos quem causou o evento
create or replace function public.pex_notificar_admins(p_tipo text, p_titulo text, p_texto text, p_alvo_tipo text, p_alvo_id text, p_chave text default null, p_exceto uuid default null)
returns void language sql security definer set search_path = public as $$
  insert into public.pex_notificacoes(usuario, tipo, titulo, texto, alvo_tipo, alvo_id, chave)
  select p.id, p_tipo, p_titulo, coalesce(p_texto, ''), p_alvo_tipo, p_alvo_id, case when p_chave is null then null else p_chave end
    from public.pex_perfis p where p.papel in ('admin','master') and p.id is distinct from p_exceto
  on conflict (usuario, chave) do nothing
$$;

create or replace function public.pex_nome_parque(p_id text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select data->>'nome' from public.pex_eventos where id = p_id), p_id)
$$;
create or replace function public.pex_nome_usuario(p_id uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(nome, '') from public.pex_perfis where id = p_id), 'Auditor')
$$;

-- auditoria enviada / ocorrência crítica
create or replace function public.pex_notif_visita() returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if (new.data->>'enviadoEm') is not null and (tg_op = 'INSERT' or (old.data->>'enviadoEm') is distinct from (new.data->>'enviadoEm')) then
    perform public.pex_notificar_admins('auditoria_enviada', 'Nova auditoria enviada',
      public.pex_nome_parque(new.data->>'evento') || ' · ' || coalesce(new.data->>'codigo', '') || ' · por ' || public.pex_nome_usuario(new.auditor),
      'visita', new.id, null, new.auditor);
    select count(*) into n from jsonb_array_elements(coalesce(new.data->'ocorrencias', '[]'::jsonb)) o where o->>'crit' = 'critica';
    if n > 0 then
      perform public.pex_notificar_admins('critica', 'Ocorrência crítica registrada',
        public.pex_nome_parque(new.data->>'evento') || ' · ' || n || ' ocorrência(s) crítica(s) na auditoria ' || coalesce(new.data->>'codigo', ''),
        'visita', new.id, 'critica:' || new.id || ':' || (new.data->>'enviadoEm'), new.auditor);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists pex_visitas_notif on public.pex_visitas;
create trigger pex_visitas_notif after insert or update on public.pex_visitas for each row execute function public.pex_notif_visita();

-- auditoria devolvida (auditor e administração)
create or replace function public.pex_notif_validacao() returns trigger language plpgsql security definer set search_path = public as $$
declare v public.pex_visitas; ant text;
begin
  if tg_op = 'UPDATE' then ant := old.data->>'status'; end if;
  if new.data->>'status' = 'devolvida' and ant is distinct from 'devolvida' then
    select * into v from public.pex_visitas where id = new.id;
    if v.auditor is not null then
      insert into public.pex_notificacoes(usuario, tipo, titulo, texto, alvo_tipo, alvo_id)
      values (v.auditor, 'auditoria_devolvida', 'Sua auditoria foi devolvida',
              public.pex_nome_parque(v.data->>'evento') || ' · ' || coalesce(v.data->>'codigo', '') || coalesce(' · ' || nullif(new.data->>'obs', ''), ''), 'visita', new.id);
    end if;
    perform public.pex_notificar_admins('auditoria_devolvida', 'Auditoria devolvida ao auditor',
      public.pex_nome_parque(v.data->>'evento') || ' · ' || coalesce(v.data->>'codigo', ''), 'visita', new.id, null, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists pex_validacoes_notif on public.pex_validacoes;
create trigger pex_validacoes_notif after insert or update on public.pex_validacoes for each row execute function public.pex_notif_validacao();

-- ações: nova, aguardando validação, aprovada, rejeitada
create or replace function public.pex_notif_acao() returns trigger language plpgsql security definer set search_path = public as $$
declare cod text := 'AC-' || lpad(new.numero::text, 4, '0'); p text := public.pex_nome_parque(new.evento);
begin
  if tg_op = 'INSERT' then
    perform public.pex_notificar_admins(case when new.criticidade = 'critica' then 'critica' else 'acao_nova' end,
      case when new.criticidade = 'critica' then 'Nova ação crítica' else 'Nova ação corretiva' end, cod || ' · ' || p || ' · ' || new.problema, 'acao', new.id, null, auth.uid());
  elsif new.status is distinct from old.status then
    if new.status = 'aguardando_validacao' then
      perform public.pex_notificar_admins('acao_aguardando', 'Correção aguardando validação', cod || ' · ' || p || ' · ' || new.problema, 'acao', new.id, null, auth.uid());
    elsif new.status = 'concluida' then
      perform public.pex_notificar_admins('correcao_aprovada', 'Correção aprovada', cod || ' · ' || p || ' · ' || new.problema, 'acao', new.id, null, auth.uid());
    elsif new.status = 'reaberta' and old.status = 'aguardando_validacao' then
      perform public.pex_notificar_admins('correcao_rejeitada', 'Correção rejeitada', cod || ' · ' || p || ' · ' || new.problema, 'acao', new.id, null, auth.uid());
    end if;
  end if;
  return new;
end $$;
drop trigger if exists pex_acoes_notif on public.pex_acoes;
create trigger pex_acoes_notif after insert or update on public.pex_acoes for each row execute function public.pex_notif_acao();

-- prazos: chamada pelo app da administração ao abrir (idempotente; pode virar tarefa agendada)
create or replace function public.pex_verificar_prazos() returns int language plpgsql security definer set search_path = public as $$
declare a record; n int := 0;
begin
  if not public.pex_admin() then return 0; end if;
  for a in select * from public.pex_acoes where status in ('aberta','em_andamento','reaberta') and prazo is not null loop
    if a.prazo < current_date then
      perform public.pex_notificar_admins('acao_atrasada', 'Ação atrasada', 'AC-' || lpad(a.numero::text, 4, '0') || ' · ' || public.pex_nome_parque(a.evento) || ' · prazo ' || to_char(a.prazo, 'DD/MM'), 'acao', a.id, 'atrasada:' || a.id || ':' || a.prazo, null);
      n := n + 1;
    elsif a.prazo <= current_date + 2 then
      perform public.pex_notificar_admins('acao_vencendo', 'Ação perto do prazo', 'AC-' || lpad(a.numero::text, 4, '0') || ' · ' || public.pex_nome_parque(a.evento) || ' · vence ' || to_char(a.prazo, 'DD/MM'), 'acao', a.id, 'vence:' || a.id || ':' || a.prazo, null);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- marcar como lida (só as próprias)
create or replace function public.pex_notif_lidas(p_ids bigint[] default null) returns int language sql security definer set search_path = public as $$
  with u as (update public.pex_notificacoes set lida_em = now() where usuario = auth.uid() and lida_em is null and (p_ids is null or id = any(p_ids)) returning 1)
  select count(*)::int from u
$$;

revoke execute on function public.pex_notificar_admins(text, text, text, text, text, text, uuid), public.pex_notif_visita(), public.pex_notif_validacao(), public.pex_notif_acao(), public.pex_nome_parque(text), public.pex_nome_usuario(uuid) from public, anon, authenticated;
revoke execute on function public.pex_verificar_prazos(), public.pex_notif_lidas(bigint[]) from public, anon;
grant execute on function public.pex_verificar_prazos(), public.pex_notif_lidas(bigint[]) to authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pex_notificacoes') then
    execute 'alter publication supabase_realtime add table public.pex_notificacoes';
  end if;
end $$;
