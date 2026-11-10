# Plataforma PEX · app web instalável

App do Programa de Excelência e Auditoria (Evento Kids). É o mesmo fluxo do protótipo (8 etapas da visita, fotos, notas, ocorrências, validação e painel), agora com banco próprio no Supabase, login por e-mail e senha e instalação na tela inicial do celular.

## O que tem na pasta

| Arquivo | Para que serve |
|---|---|
| `index.html` | O app inteiro (telas e regras do manual PEX) |
| `config.js` | **Onde você cola o endereço e a chave do Supabase** |
| `js/backend.js` | Ligação com o Supabase (banco, login, fotos, tempo real) |
| `js/supabase.min.js` | Biblioteca oficial do Supabase (v2.45.4) |
| `supabase/001_schema.sql` | Tabelas, regras de segurança e pasta de fotos |
| `supabase/002_login_master.sql` | Login master: exclusão de logins, permissões e senha provisória |
| `manifest.webmanifest`, `sw.js`, `icons/` | Instalação como app e abertura sem sinal |

## Passo a passo para colocar no ar

### 1. Criar o projeto no Supabase (conta nova)
1. Em supabase.com, crie um projeto. Use a região **South America (São Paulo)**.
2. Abra **SQL Editor › New query** e rode, nesta ordem, `supabase/001_schema.sql` e `supabase/002_login_master.sql`.

### 2. Ajustar o login
Em **Authentication**:
- **Sign In / Providers › Email**: desligue **Confirm email**. O e-mail gratuito do Supabase só manda poucas mensagens por hora, e a liberação de cada pessoa já é feita pela administração dentro do app.
- **URL Configuration**: em **Site URL**, coloque o endereço onde o app ficar publicado (passo 4). Isso é necessário para o link de "Esqueci a senha" funcionar.

### 3. Ligar o app ao projeto
Em **Project Settings › API**, copie a **Project URL** e a chave **anon / publishable** para o `config.js`:

```js
window.PEX_CONFIG = {
  SUPABASE_URL: 'https://xxxxxxxx.supabase.co',
  SUPABASE_ANON_KEY: 'eyJ...'
};
```

A chave anon pode ficar no app: quem protege os dados são as regras do `schema.sql`. **Nunca** coloque a chave `service_role` aqui.

### 4. Publicar
Publicado em **https://danillohdf.github.io/pex/**. O app é só um conjunto de arquivos e precisa de um endereço **https**. Opções gratuitas:
- **Netlify Drop** (mais fácil): acesse app.netlify.com/drop e arraste a pasta `pex-app`.
- **GitHub Pages** ou **Vercel**, se preferir manter num repositório.

### 5. Primeiro acesso
1. Abra o endereço e toque em **Criar acesso**. **O primeiro cadastro vira o login master automaticamente.**
2. Na aba **Painel**, em **Adicionar eventos**, cole a lista dos 43 eventos, um por linha. Se quiser, informe também a franquia e se o evento tem infláveis, separados por ponto e vírgula: `Shopping X; Franquia SP; Sim`.
3. Cada auditor cria o próprio acesso e entra como **Aguardando liberação**. Na aba **Usuários**, mude essa pessoa para **Auditor**. Quem também for validar visitas recebe **Administração**.

### Instalar no celular
- **iPhone (Safari)**: Compartilhar › Adicionar à Tela de Início.
- **Android (Chrome)**: menu ⋮ › Instalar app (ou Adicionar à tela inicial).

## Quem pode o quê

| Perfil | Pode |
|---|---|
| Aguardando liberação / Bloqueado | Só ver a tela de espera |
| Auditor | Ver o painel, criar visitas e editar **as suas** enquanto estão em preenchimento ou foram devolvidas, e enviar fotos |
| Administração | Tudo do auditor, mais validar, devolver, montar plano de ação, encerrar, cadastrar eventos e liberar ou bloquear auditores |
| Master (só um) | Tudo da Administração, mais nomear ou remover administradores, excluir logins, definir senha provisória e confirmar e-mail |

Essas regras valem no próprio banco (RLS), não só nas telas.

## Espaço no plano gratuito
- O app reduz cada foto para no máximo 1600 px antes de enviar, o que dá uns 200 a 400 KB por foto.
- Uma visita com cerca de 10 fotos ocupa uns 3 MB, então uma rodada nos 43 eventos fica entre 100 e 150 MB. O plano gratuito tem 1 GB para fotos.

## Atualizar o app depois
Ao mudar qualquer arquivo, aumente `VERSAO` em `sw.js` (hoje `pex-v4`) e publique de novo. Assim os celulares baixam a versão nova.
