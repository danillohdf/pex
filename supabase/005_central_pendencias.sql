-- =====================================================================
-- PEX 2.0 · Fase 2 · Central de Pendências (ações corretivas)
-- Só acrescenta estruturas. Não altera nem apaga dados existentes.
-- As ações que hoje estão dentro de pex_validacoes.data.acoes são COPIADAS
-- para a tabela nova (o JSON original continua onde está).
-- =====================================================================

-- ---------- Tabela de ações ----------
create table if not exists public.pex_acoes (
  id              text primary key default ('ac_' || replace(gen_random_uuid()::text, '-', '')),
  numero          bigint generated always as identity unique,
  evento          text not null references public.pex_eventos(id),
  visita          text references public.pex_visitas(id) on delete set null,
  ocorrencia      text,                         -- id da ocorrência dentro da auditoria (oc...)
  item            text,                         -- id do item do checklist (quando houver)
  origem          text not null default 'manual' check (origem in ('ocorrencia','nao_conformidade','manual')),
  identificado_em date not null default current_date,
  problema        text not null check (length(trim(problema)) > 0),
  local           text not null default '',
  eixo            text check (eixo in ('atendimento','organizacao','auditoria','estrutura')),
  criticidade     text not null default 'media' check (criticidade in ('critica','alta','media','baixa')),
  departamento    text check (departamento in ('lider','compras','operacoes','manutencao','gestao')),
  responsavel     text not null default '',     -- nome de quem executa (não é usuário do sistema)
  acao            text not null default '',     -- ação necessária
  prazo           date,
  status          text not null default 'aberta' check (status in ('aberta','em_andamento','aguardando_validacao','concluida','reaberta')),
  fotos           jsonb not null default '[]'::jsonb,   -- fotos do problema (caminhos no bucket)
  evidencias      jsonb not null default '[]'::jsonb,   -- [{tipo, texto, fotos, em, por}]
  observacoes     text not null default '',
  criado_por      uuid default auth.uid() references auth.users(id) on delete set null,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  concluido_em    timestamptz,
  unique (visita, ocorrencia)
);
create index if not exists pex_acoes_evento_idx on public.pex_acoes(evento);
create index if not exists pex_acoes_status_idx on public.pex_acoes(status);
create index if not exists pex_acoes_visita_idx on public.pex_acoes(visita);

-- ---------- Histórico (só o banco escreve) ----------
create table if not exists public.pex_acoes_hist (
  id        bigint generated always as identity primary key,
  acao_id   text not null references public.pex_acoes(id) on delete cascade,
  em        timestamptz not null default now(),
  por       uuid default auth.uid() references auth.users(id) on delete set null,
  tipo      text not null,                  -- criada | campo | status | evidencia
  campo     text,
  de        text,
  para      text,
  texto     text
);
create index if not exists pex_acoes_hist_acao_idx on public.pex_acoes_hist(acao_id, em);

-- ---------- Regras: status só muda pela função de transição ----------
create or replace function public.pex_acao_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id; new.numero := old.numero; new.criado_em := old.criado_em; new.criado_por := old.criado_por;
    new.evento := old.evento; new.visita := old.visita; new.ocorrencia := old.ocorrencia; new.origem := old.origem;
    if new.status is distinct from old.status and coalesce(current_setting('pex.transicao', true), '') <> '1' then
      raise exception 'O status de uma ação só muda pelos botões de fluxo (iniciar, informar correção, aprovar, rejeitar, reabrir)' using errcode = '42501';
    end if;
    if coalesce(current_setting('pex.transicao', true), '') <> '1' then
      new.evidencias := old.evidencias;  -- evidências só entram pela função de transição/registro
    end if;
    new.atualizado_em := now();
  end if;
  return new;
end $$;
drop trigger if exists pex_acoes_guard on public.pex_acoes;
create trigger pex_acoes_guard before update on public.pex_acoes for each row execute function public.pex_acao_guard();

-- Histórico automático de criação e de cada campo alterado
create or replace function public.pex_acao_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text; a jsonb; b jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.pex_acoes_hist(acao_id, tipo, para, texto) values (new.id, 'criada', new.status, new.problema);
    return new;
  end if;
  a := to_jsonb(old); b := to_jsonb(new);
  foreach c in array array['problema','local','eixo','criticidade','departamento','responsavel','acao','prazo','observacoes'] loop
    if (a->>c) is distinct from (b->>c) then
      insert into public.pex_acoes_hist(acao_id, tipo, campo, de, para) values (new.id, 'campo', c, a->>c, b->>c);
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists pex_acoes_log on public.pex_acoes;
create trigger pex_acoes_log after insert or update on public.pex_acoes for each row execute function public.pex_acao_log();

-- ---------- Transição de status (com evidência ou motivo) ----------
-- aberta | reaberta  -> em_andamento | aguardando_validacao
-- em_andamento       -> aguardando_validacao
-- aguardando_validacao -> concluida (aprovar) | reaberta (rejeitar, motivo obrigatório)
-- concluida          -> reaberta (motivo obrigatório)
create or replace function public.pex_acao_transicao(p_id text, p_para text, p_texto text default '', p_fotos jsonb default '[]'::jsonb)
returns public.pex_acoes
language plpgsql security definer set search_path = public as $$
declare a public.pex_acoes; ok boolean; de_status text; txt text := coalesce(trim(p_texto), ''); fts jsonb := coalesce(p_fotos, '[]'::jsonb);
begin
  if not public.pex_admin() then raise exception 'Só a administração altera o status das ações' using errcode = '42501'; end if;
  select * into a from public.pex_acoes where id = p_id for update;
  if not found then raise exception 'Ação não encontrada' using errcode = 'P0002'; end if;
  de_status := a.status;
  ok := (a.status in ('aberta','reaberta') and p_para in ('em_andamento','aguardando_validacao'))
     or (a.status = 'em_andamento' and p_para = 'aguardando_validacao')
     or (a.status = 'aguardando_validacao' and p_para in ('concluida','reaberta'))
     or (a.status = 'concluida' and p_para = 'reaberta');
  if not ok then raise exception 'Mudança de status não permitida: % → %', a.status, p_para using errcode = '22023'; end if;
  if p_para = 'aguardando_validacao' and txt = '' and jsonb_array_length(fts) = 0 then
    raise exception 'Para informar a correção, descreva o que foi feito ou anexe uma foto' using errcode = '22023';
  end if;
  if p_para = 'reaberta' and txt = '' then
    raise exception 'Informe o motivo para rejeitar ou reabrir a ação' using errcode = '22023';
  end if;
  perform set_config('pex.transicao', '1', true);
  update public.pex_acoes set
    status = p_para,
    concluido_em = case when p_para = 'concluida' then now() when p_para = 'reaberta' then null else concluido_em end,
    evidencias = case when p_para = 'aguardando_validacao'
      then evidencias || jsonb_build_array(jsonb_build_object('tipo','correcao','texto',txt,'fotos',fts,'em',now(),'por',auth.uid()))
      else evidencias end
  where id = p_id returning * into a;
  perform set_config('pex.transicao', '', true);
  insert into public.pex_acoes_hist(acao_id, tipo, de, para, texto) values (p_id, 'status', de_status, p_para, nullif(txt, ''));
  return a;
end $$;

-- Evidência avulsa (anotação ou foto) sem mudar status
create or replace function public.pex_acao_evidencia(p_id text, p_texto text default '', p_fotos jsonb default '[]'::jsonb)
returns public.pex_acoes
language plpgsql security definer set search_path = public as $$
declare a public.pex_acoes; txt text := coalesce(trim(p_texto), ''); fts jsonb := coalesce(p_fotos, '[]'::jsonb);
begin
  if not public.pex_admin() then raise exception 'Só a administração registra evidências' using errcode = '42501'; end if;
  if txt = '' and jsonb_array_length(fts) = 0 then raise exception 'Escreva a evidência ou anexe uma foto' using errcode = '22023'; end if;
  perform set_config('pex.transicao', '1', true);
  update public.pex_acoes set evidencias = evidencias || jsonb_build_array(jsonb_build_object('tipo','registro','texto',txt,'fotos',fts,'em',now(),'por',auth.uid()))
    where id = p_id returning * into a;
  perform set_config('pex.transicao', '', true);
  if not found then raise exception 'Ação não encontrada' using errcode = 'P0002'; end if;
  insert into public.pex_acoes_hist(acao_id, tipo, texto) values (p_id, 'evidencia', nullif(txt, ''));
  return a;
end $$;

-- ---------- Segurança ----------
alter table public.pex_acoes enable row level security;
alter table public.pex_acoes_hist enable row level security;

drop policy if exists "acoes: admin ve" on public.pex_acoes;
create policy "acoes: admin ve" on public.pex_acoes for select to authenticated using (public.pex_admin());
drop policy if exists "acoes: admin cria" on public.pex_acoes;
create policy "acoes: admin cria" on public.pex_acoes for insert to authenticated
  with check (public.pex_admin() and status = 'aberta' and evidencias = '[]'::jsonb);
drop policy if exists "acoes: admin altera" on public.pex_acoes;
create policy "acoes: admin altera" on public.pex_acoes for update to authenticated using (public.pex_admin()) with check (public.pex_admin());
-- sem política de DELETE: ações não são apagadas pelo app (preserva o histórico)

drop policy if exists "acoes hist: admin ve" on public.pex_acoes_hist;
create policy "acoes hist: admin ve" on public.pex_acoes_hist for select to authenticated using (public.pex_admin());
-- sem INSERT/UPDATE/DELETE para usuários: só os gatilhos e funções escrevem

grant select, insert, update on public.pex_acoes to authenticated;
grant select on public.pex_acoes_hist to authenticated;
revoke execute on function public.pex_acao_transicao(text, text, text, jsonb), public.pex_acao_evidencia(text, text, jsonb), public.pex_acao_guard(), public.pex_acao_log() from public, anon;
grant execute on function public.pex_acao_transicao(text, text, text, jsonb), public.pex_acao_evidencia(text, text, jsonb) to authenticated;

-- ---------- Tempo real ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pex_acoes') then
    execute 'alter publication supabase_realtime add table public.pex_acoes';
  end if;
end $$;

-- ---------- Cópia das ações existentes (não destrutiva, pode rodar de novo) ----------
-- Para cada ocorrência de auditoria já enviada, cria a ação correspondente.
-- Responsável/prazo/status vêm do plano de ação antigo (pex_validacoes.data.acoes), quando houver.
insert into public.pex_acoes (evento, visita, ocorrencia, item, origem, identificado_em, problema, local, eixo, criticidade,
                              departamento, responsavel, acao, prazo, status, fotos, evidencias, observacoes, criado_por, criado_em, concluido_em)
select v.data->>'evento', v.id, oc->>'id', nullif(oc->>'item',''), 'ocorrencia',
       coalesce(to_timestamp(((v.data->>'enviadoEm')::numeric) / 1000)::date, current_date),
       coalesce(nullif(trim(oc->>'desc'),''), 'Ocorrência sem descrição'),
       coalesce(oc->>'local',''),
       case when oc->>'eixo' in ('atendimento','organizacao','auditoria','estrutura') then oc->>'eixo' end,
       case when oc->>'crit' in ('critica','alta','media','baixa') then oc->>'crit' else 'media' end,
       case w.data->'acoes'->(oc->>'id')->>'resp'
         when 'Líder do evento' then 'lider' when 'Compras' then 'compras' when 'Operações' then 'operacoes'
         when 'Manutenção' then 'manutencao' when 'Gestão PEX' then 'gestao' end,
       case when w.data->'acoes'->(oc->>'id')->>'resp' in ('Líder do evento','Compras','Operações','Manutenção','Gestão PEX') then ''
            else coalesce(w.data->'acoes'->(oc->>'id')->>'resp','') end,
       coalesce(oc->>'acao',''),
       nullif(w.data->'acoes'->(oc->>'id')->>'prazo','')::date,
       case w.data->'acoes'->(oc->>'id')->>'status' when 'resolvida' then 'concluida' when 'andamento' then 'em_andamento' else 'aberta' end,
       coalesce(oc->'fotos','[]'::jsonb),
       case when coalesce(w.data->'acoes'->(oc->>'id')->>'obs','') <> '' or jsonb_array_length(coalesce(w.data->'acoes'->(oc->>'id')->'fotos','[]'::jsonb)) > 0
            then jsonb_build_array(jsonb_build_object('tipo','correcao','texto',coalesce(w.data->'acoes'->(oc->>'id')->>'obs',''),'fotos',coalesce(w.data->'acoes'->(oc->>'id')->'fotos','[]'::jsonb),'em',now(),'por',null,'migrado',true))
            else '[]'::jsonb end,
       '',
       v.auditor, now(),
       case when w.data->'acoes'->(oc->>'id')->>'status' = 'resolvida' then now() end
from public.pex_visitas v
cross join lateral jsonb_array_elements(coalesce(v.data->'ocorrencias','[]'::jsonb)) oc
left join public.pex_validacoes w on w.id = v.id
where (v.data->>'enviadoEm') is not null and (v.data->>'evento') in (select id from public.pex_eventos)
on conflict (visita, ocorrencia) do nothing;

-- Funções de gatilho não precisam ser chamáveis por usuários (aviso do Security Advisor)
revoke execute on function public.pex_acao_log(), public.pex_acao_guard(), public.pex_perfil_guard() from authenticated;
