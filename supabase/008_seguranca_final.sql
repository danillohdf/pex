-- =====================================================================
-- Plataforma PEX 2.0 · Fase 7 · segurança final (rodar depois do 007)
-- Não apaga nem altera dados existentes.
-- 1. Fim do "primeiro cadastro vira master": todo cadastro novo nasce pendente.
-- 2. Validação no servidor do envio da auditoria (regras básicas).
-- =====================================================================

-- 1. Bootstrap ----------------------------------------------------------
-- Antes, se não existisse nenhum admin/master (por exemplo, depois de uma
-- exclusão por engano), o próximo cadastro público virava master.
-- Agora todo cadastro entra como 'pendente'. Promover alguém a master é
-- feito só pelo SQL Editor do Supabase (ver docs/SEGURANCA.md).
create or replace function public.pex_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.pex_perfis (id, nome, email, papel)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
    coalesce(new.email, ''),
    'pendente'
  )
  on conflict (id) do nothing;
  return new;
end $$;
revoke execute on function public.pex_novo_usuario() from public, anon, authenticated;

-- 2. Envio da auditoria -------------------------------------------------
-- O app já confere tudo antes de enviar. Aqui o banco confere o mínimo,
-- para que um envio incompleto não entre nem por fora do app.
-- Só roda quando "enviadoEm" é preenchido ou muda; rascunhos e registros
-- antigos não são afetados.
create or replace function public.pex_visita_envio_guard() returns trigger
language plpgsql set search_path = public as $$
declare d jsonb := new.data; falta text[] := '{}'; o jsonb;
begin
  if (d->>'enviadoEm') is null then return new; end if;
  if tg_op = 'UPDATE' and (old.data->>'enviadoEm') is not distinct from (d->>'enviadoEm') then return new; end if;

  if coalesce(d->>'evento', '') = '' or not exists (select 1 from public.pex_eventos e where e.id = d->>'evento') then
    falta := array_append(falta, 'parque'); end if;
  if (d->>'identificadoEm') is null then
    falta := array_append(falta, 'identificação ao líder'); end if;
  if jsonb_typeof(d->'atendentes') is distinct from 'array'
     or not exists (select 1 from jsonb_array_elements_text(d->'atendentes') x where trim(x) <> '') then
    falta := array_append(falta, 'quem atendeu'); end if;
  if jsonb_typeof(d->'itens') is distinct from 'object'
     or not exists (select 1 from jsonb_each(d->'itens') i where coalesce(i.value->>'r', '') <> '') then
    falta := array_append(falta, 'respostas do checklist'); end if;
  if jsonb_typeof(d->'notas') is distinct from 'object'
     or not exists (select 1 from jsonb_each(d->'notas') n where n.value ? 'n' and n.value->>'n' is not null)
     or exists (select 1 from jsonb_each(d->'notas') n where n.value->>'n' is not null and trim(coalesce(n.value->>'j', '')) = '') then
    falta := array_append(falta, 'notas com justificativa'); end if;
  if jsonb_typeof(d->'ocorrencias') = 'array' then
    for o in select * from jsonb_array_elements(d->'ocorrencias') loop
      if trim(coalesce(o->>'local', '')) = '' or trim(coalesce(o->>'desc', '')) = '' or coalesce(o->>'crit', '') = '' then
        falta := array_append(falta, 'ocorrência sem local, descrição ou criticidade'); exit; end if;
      if o->>'crit' = 'critica' and coalesce(o->>'comunicado', '') in ('', 'false') then
        falta := array_append(falta, 'ocorrência crítica sem comunicação à liderança'); exit; end if;
    end loop;
  end if;

  if array_length(falta, 1) > 0 then
    raise exception 'Auditoria incompleta, não pode ser enviada. Falta: %', array_to_string(falta, ', ')
      using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function public.pex_visita_envio_guard() from public, anon, authenticated;

drop trigger if exists pex_visitas_envio_guard on public.pex_visitas;
create trigger pex_visitas_envio_guard before insert or update on public.pex_visitas
  for each row execute function public.pex_visita_envio_guard();
