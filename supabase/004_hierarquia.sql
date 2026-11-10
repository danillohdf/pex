-- Plataforma PEX · hierarquia: auditor só vê o que ele mesmo fez; administração e master veem tudo.
drop policy if exists "visitas: ver" on public.pex_visitas;
create policy "visitas: ver" on public.pex_visitas for select to authenticated
  using (public.pex_admin() or (public.pex_ativo() and auditor = auth.uid()));

drop policy if exists "validacoes: ver" on public.pex_validacoes;
create policy "validacoes: ver" on public.pex_validacoes for select to authenticated
  using (public.pex_admin() or exists (select 1 from public.pex_visitas v where v.id = pex_validacoes.id and v.auditor = auth.uid() and public.pex_ativo()));

drop policy if exists "perfis: ver" on public.pex_perfis;
create policy "perfis: ver" on public.pex_perfis for select to authenticated
  using (id = auth.uid() or public.pex_admin());

drop policy if exists "pex fotos: ver" on storage.objects;
create policy "pex fotos: ver" on storage.objects for select to authenticated
  using (bucket_id = 'pex-fotos' and (public.pex_admin() or (public.pex_ativo() and (storage.foldername(name))[1] = auth.uid()::text)));
