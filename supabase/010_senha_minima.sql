-- =====================================================================
-- Plataforma PEX · senha mínima de 8 caracteres (rodar depois do 009)
-- Vale para a senha provisória que o master define. Senhas atuais não mudam
-- e continuam entrando normalmente. Não altera dados.
-- Para cadastro e troca de senha, o limite fica no painel do Supabase:
-- Authentication › Sign In / Providers › Email › Minimum password length = 8.
-- =====================================================================
create or replace function public.pex_definir_senha(alvo uuid, senha text) returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if not public.pex_master() then raise exception 'Só o master define senhas' using errcode = '42501'; end if;
  if length(coalesce(senha,'')) < 8 then raise exception 'A senha precisa ter pelo menos 8 caracteres' using errcode = '22023'; end if;
  update auth.users set encrypted_password = extensions.crypt(senha, extensions.gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
  where id = alvo;
end $$;
