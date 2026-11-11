-- =====================================================================
-- Plataforma PEX 2.0 · Fase 7 · desempenho das regras de acesso (rodar depois do 008)
-- Mesmas regras de antes; só muda a forma de escrever: (select auth.uid())
-- e (select pex_admin()) são avaliados uma vez por consulta, não por linha.
-- Também cria índices para duas chaves estrangeiras. Não altera dados.
-- =====================================================================
drop policy if exists "visitas: auditor cria" on public.pex_visitas;
create policy "visitas: auditor cria" on public.pex_visitas for insert to authenticated
  with check ((select public.pex_ativo()) and auditor = (select auth.uid()) and (data->>'enviadoEm') is null);

drop policy if exists "visitas: auditor edita" on public.pex_visitas;
create policy "visitas: auditor edita" on public.pex_visitas for update to authenticated
  using ((select public.pex_ativo()) and public.pex_visita_editavel(pex_visitas.*))
  with check (auditor = (select auth.uid()));

drop policy if exists "visitas: ver" on public.pex_visitas;
create policy "visitas: ver" on public.pex_visitas for select to authenticated
  using ((select public.pex_admin()) or ((select public.pex_ativo()) and auditor = (select auth.uid())));

drop policy if exists "validacoes: ver" on public.pex_validacoes;
create policy "validacoes: ver" on public.pex_validacoes for select to authenticated
  using ((select public.pex_admin()) or exists (select 1 from public.pex_visitas v
    where v.id = pex_validacoes.id and v.auditor = (select auth.uid()) and (select public.pex_ativo())));

drop policy if exists "perfis: ver" on public.pex_perfis;
create policy "perfis: ver" on public.pex_perfis for select to authenticated
  using (id = (select auth.uid()) or (select public.pex_admin()));

drop policy if exists "notif: dono ve" on public.pex_notificacoes;
create policy "notif: dono ve" on public.pex_notificacoes for select to authenticated
  using (usuario = (select auth.uid()));

create index if not exists pex_acoes_criado_por_idx on public.pex_acoes(criado_por);
create index if not exists pex_acoes_hist_por_idx on public.pex_acoes_hist(por);
