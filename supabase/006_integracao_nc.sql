-- =====================================================================
-- PEX 2.0 · Fase 3 · Integração: nenhuma não conformidade sem acompanhamento
-- Só acrescenta estruturas. Não altera dados.
-- Chaves de não conformidade de uma auditoria:
--   item:<id>  item do checklist marcado como não conforme
--   ext:<id>   "outro local" marcado como não conforme
--   oc:<id>    ocorrência registrada sem item de origem
-- Cobertura: existe ação na Central (pex_acoes.item = <id> ou 'ext:<id>', ou
-- pex_acoes.ocorrencia = <id>) OU justificativa da administração em
-- pex_validacoes.data.justificativas[<chave>].texto
-- =====================================================================

-- uma ação por item de uma mesma auditoria
create unique index if not exists pex_acoes_visita_item_uidx on public.pex_acoes(visita, item) where item is not null and visita is not null;

create or replace function public.pex_nc_pendentes(p_visita text, p_just jsonb default null)
returns setof text
language sql stable security definer set search_path = public as $$
  with v as (select data from public.pex_visitas where id = p_visita),
  j as (select coalesce(p_just, (select data->'justificativas' from public.pex_validacoes where id = p_visita), '{}'::jsonb) as js),
  nc as (
    select 'item:' || e.key as chave, e.key as item, null::text as oc
      from v, jsonb_each(coalesce(v.data->'itens', '{}'::jsonb)) e
     where e.value->>'r' = 'nc'
       and (left(e.key, 3) <> 'if-' or coalesce((v.data->>'temInflaveis')::boolean, false))
    union all
    select 'ext:' || (x->>'id'), 'ext:' || (x->>'id'), null
      from v, jsonb_each(case when jsonb_typeof(v.data->'extras') = 'object' then v.data->'extras' else '{}'::jsonb end) e,
           jsonb_array_elements(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) x
     where x->>'r' = 'nc'
    union all
    select 'oc:' || (o->>'id'), null, o->>'id'
      from v, jsonb_array_elements(coalesce(v.data->'ocorrencias', '[]'::jsonb)) o
     where coalesce(o->>'item', '') = '' and coalesce(o->>'ext', '') = ''
  )
  select nc.chave from nc, j
   where not exists (select 1 from public.pex_acoes a where a.visita = p_visita and ((nc.item is not null and a.item = nc.item) or (nc.oc is not null and a.ocorrencia = nc.oc)))
     and coalesce(trim(j.js->nc.chave->>'texto'), '') = ''
$$;

-- Trava: validar/encerrar só com todas as não conformidades acompanhadas;
-- encerrar só com todas as ações da auditoria concluídas.
create or replace function public.pex_validacao_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text := new.data->>'status'; ant text; n int;
begin
  if tg_op = 'UPDATE' then ant := old.data->>'status'; end if;
  if st in ('validado','encerrado') and st is distinct from ant then
    select count(*) into n from public.pex_nc_pendentes(new.id, new.data->'justificativas');
    if n > 0 then
      raise exception 'Existem % não conformidade(s) sem ação corretiva nem justificativa. Trate todas antes de validar.', n using errcode = '23514';
    end if;
  end if;
  if st = 'encerrado' and st is distinct from ant then
    select count(*) into n from public.pex_acoes where visita = new.id and status <> 'concluida';
    if n > 0 then
      raise exception 'Existem % ação(ões) corretiva(s) desta auditoria ainda não concluída(s).', n using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists pex_validacoes_guard on public.pex_validacoes;
create trigger pex_validacoes_guard before insert or update on public.pex_validacoes for each row execute function public.pex_validacao_guard();

revoke execute on function public.pex_nc_pendentes(text, jsonb) from public, anon;
grant execute on function public.pex_nc_pendentes(text, jsonb) to authenticated;
revoke execute on function public.pex_validacao_guard() from public, anon, authenticated;
