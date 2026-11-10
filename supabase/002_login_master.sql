-- =====================================================================
-- Plataforma PEX · login master (rodar depois do 001_schema.sql)
-- Master: único, gerencia administradores, exclui logins e define senha provisória.
-- Administração: libera/bloqueia auditores, valida visitas e cadastra eventos.
-- =====================================================================
alter table public.pex_perfis drop constraint if exists pex_perfis_papel_check;
alter table public.pex_perfis add constraint pex_perfis_papel_check check (papel in ('pendente','auditor','admin','master','bloqueado'));

create or replace function public.pex_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select public.pex_papel() in ('auditor','admin','master')
$$;
create or replace function public.pex_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.pex_papel() in ('admin','master')
$$;
create or replace function public.pex_master() returns boolean
language sql stable security definer set search_path = public as $$
  select public.pex_papel() = 'master'
$$;

-- o primeiro cadastro vira master
create or replace function public.pex_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.pex_perfis (id, nome, email, papel)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
    coalesce(new.email, ''),
    case when exists (select 1 from public.pex_perfis where papel in ('admin','master')) then 'pendente' else 'master' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- hierarquia de quem pode mudar o quê
create or replace function public.pex_perfil_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare eu text := public.pex_papel();
begin
  if auth.uid() is null then return new; end if; -- SQL do painel do Supabase
  new.id := old.id; new.email := old.email; new.criado_em := old.criado_em;
  if old.papel = 'master' and new.papel <> 'master' then raise exception 'O login master não pode ser alterado pelo app' using errcode = '42501'; end if;
  if new.papel = 'master' and old.papel <> 'master' then raise exception 'Só existe um login master' using errcode = '42501'; end if;
  if eu = 'admin' then
    if old.papel in ('admin','master') or new.papel in ('admin','master') then
      raise exception 'Só o master gerencia administradores' using errcode = '42501';
    end if;
  elsif eu <> 'master' then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists pex_perfis_guard on public.pex_perfis;
create trigger pex_perfis_guard before update on public.pex_perfis for each row execute function public.pex_perfil_guard();

-- visitas continuam no histórico quando o auditor é excluído
alter table public.pex_visitas alter column auditor drop not null;
alter table public.pex_visitas drop constraint if exists pex_visitas_auditor_fkey;
alter table public.pex_visitas add constraint pex_visitas_auditor_fkey foreign key (auditor) references auth.users(id) on delete set null;

create or replace function public.pex_visita_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then new.auditor := old.auditor; end if;
  if new.auditor is not null then
    new.data := jsonb_set(new.data, '{auditor}', to_jsonb(new.auditor::text));
  end if;
  return new;
end $$;

create or replace function public.pex_excluir_usuario(alvo uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare p public.pex_perfis;
begin
  if not public.pex_master() then raise exception 'Só o master exclui logins' using errcode = '42501'; end if;
  if alvo = auth.uid() then raise exception 'Você não pode excluir o próprio login' using errcode = '42501'; end if;
  select * into p from public.pex_perfis where id = alvo;
  update public.pex_visitas set data = data || jsonb_build_object('auditorNome', coalesce(p.nome, p.email, 'Auditor excluído'), 'auditorExcluido', true)
    where auditor = alvo;
  delete from auth.users where id = alvo;
end $$;

create or replace function public.pex_definir_senha(alvo uuid, senha text) returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if not public.pex_master() then raise exception 'Só o master define senhas' using errcode = '42501'; end if;
  if length(coalesce(senha,'')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres' using errcode = '22023'; end if;
  update auth.users set encrypted_password = extensions.crypt(senha, extensions.gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
  where id = alvo;
end $$;

create or replace function public.pex_confirmar_email(alvo uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.pex_admin() then raise exception 'Sem permissão' using errcode = '42501'; end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = alvo;
end $$;

create or replace function public.pex_lista_usuarios() returns table(id uuid, nome text, email text, papel text, criado_em timestamptz, ultimo_acesso timestamptz, confirmado boolean, visitas bigint)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.nome, p.email, p.papel, p.criado_em, u.last_sign_in_at, u.email_confirmed_at is not null,
    (select count(*) from public.pex_visitas v where v.auditor = p.id)
  from public.pex_perfis p join auth.users u on u.id = p.id
  where public.pex_admin()
  order by p.criado_em
$$;

revoke execute on function public.pex_master(), public.pex_excluir_usuario(uuid), public.pex_definir_senha(uuid, text), public.pex_confirmar_email(uuid), public.pex_lista_usuarios(), public.pex_perfil_guard() from public, anon;
grant execute on function public.pex_master(), public.pex_excluir_usuario(uuid), public.pex_definir_senha(uuid, text), public.pex_confirmar_email(uuid), public.pex_lista_usuarios() to authenticated;

-- Defina aqui o e-mail do master (já aplicado no projeto plataforma-pex):
-- update public.pex_perfis set papel = 'master' where email = 'SEU-EMAIL';
