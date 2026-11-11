# Plataforma PEX · app web instalável

App do Programa de Excelência e Auditoria (Evento Kids). Auditores visitam os parques e preenchem a auditoria em 8 etapas (com fotos, notas e ocorrências). A administração valida, transforma os problemas em ações na Central de Pendências e acompanha tudo pelo dashboard. Funciona no celular (instalável) e no computador, com banco no Supabase e modo offline.

Endereço publicado: **https://danillohdf.github.io/pex/** (branch `main`, versão 2.0).

## O que tem na pasta

| Arquivo | Para que serve |
|---|---|
| `index.html` | O app inteiro (telas, rotas e regras do manual PEX) |
| `css/pex.css` | Design system: cores, tipografia, componentes, layout de celular e computador |
| `config.js` | Endereço e chave **pública** (anon) do Supabase |
| `js/backend.js` | Ligação com o Supabase: banco, login, fotos, tempo real, notificações e fila offline |
| `js/supabase.min.js` | Biblioteca oficial do Supabase (v2.45.4) |
| `supabase/001` a `009` | Migrations SQL, na ordem em que foram aplicadas (tabela abaixo) |
| `manifest.webmanifest`, `sw.js`, `icons/` | Instalação como app e abertura sem internet |
| `docs/` | Diagnóstico, design system, Central de Pendências, segurança e relatório da versão 2.0 |

## Migrations do banco

Rodar sempre na ordem. Todas são compatíveis com os dados existentes e nenhuma apaga registros.

| Arquivo | O que faz |
|---|---|
| `001_schema.sql` | Tabelas de perfis, parques, auditorias e validações; regras de acesso (RLS); pasta de fotos privada |
| `002_login_master.sql` | Papéis (pendente, auditor, admin, master, bloqueado) e funções do master |
| `003_parques.sql` | Cadastro dos 43 parques com sócio |
| `004_hierarquia.sql` | Auditor só vê o que ele fez; administração vê tudo |
| `005_central_pendencias.sql` | Ações corretivas (`pex_acoes`), histórico e fluxo de status |
| `006_integracao_nc.sql` | Toda não conformidade vira ação ou justificativa antes de validar |
| `007_notificacoes.sql` | Notificações automáticas e verificação de prazos |
| `008_seguranca_final.sql` | Fim do "primeiro cadastro vira master"; validação do envio no servidor |
| `009_desempenho_rls.sql` | Mesmas regras de acesso, escritas para rodar mais rápido; índices |
| `010_senha_minima.sql` | Senha provisória do master com no mínimo 8 caracteres |

## Configuração do Supabase

Em **Authentication**:
- **Sign In / Providers › Email**: deixe **Confirm email** desligado. A liberação de cada pessoa é feita pela administração dentro do app.
- **URL Configuration › Site URL**: `https://danillohdf.github.io/pex/` (necessário para "Esqueci a senha").
- **Sign In / Providers › Email › Minimum password length**: 8 (o app já exige 8 para senha nova).
- **Leaked password protection** (bloquear senhas vazadas): só existe nos planos pagos do Supabase (Pro em diante). No plano gratuito fica desligado.

A chave anon pode ficar no app: quem protege os dados são as regras do banco. **Nunca** coloque a chave `service_role` em nenhum arquivo do app.

## Primeiro acesso e novos usuários

- Todo cadastro novo entra como **Aguardando liberação**. A administração libera como **Auditor** em **Configurações › Usuários**; só o master nomeia **Administração**.
- O master já existe. Se um dia for preciso criar outro master (por exemplo, numa instalação nova), veja `docs/SEGURANCA.md`. Não existe mais o "primeiro cadastro vira master".

## Quem pode o quê

| Perfil | Pode |
|---|---|
| Aguardando liberação / Bloqueado | Só ver a tela de espera |
| Auditor | Criar auditorias e editar **as suas** enquanto estão em preenchimento ou foram devolvidas; ver o histórico delas e os avisos |
| Administração | Tudo do auditor, mais validar e devolver, Central de Pendências, dashboard executivo, parques, relatórios em PDF e liberar ou bloquear auditores |
| Master (só um) | Tudo da Administração, mais nomear ou remover administradores, excluir logins, definir senha provisória e confirmar e-mail |

Essas regras valem no próprio banco (RLS e funções), não só nas telas.

## Sem internet

O auditor pode abrir o app, preencher e até enviar uma auditoria sem sinal. Tudo fica guardado no aparelho (inclusive as fotos) e é enviado sozinho quando a conexão volta. O indicador no topo mostra: Online, Offline, alterações pendentes, Sincronizando ou erro.

## Instalar no celular
- **iPhone (Safari)**: Compartilhar › Adicionar à Tela de Início.
- **Android (Chrome)**: menu ⋮ › Instalar app.

## Espaço no plano gratuito
Cada foto é reduzida para no máximo 1600 px (uns 200 a 400 KB). Uma rodada nos 43 parques fica entre 100 e 150 MB; o plano gratuito tem 1 GB para fotos.

## Atualizar o app depois
1. Trabalhe numa branch separada (a 2.0 foi feita em `pex-2.0`).
2. Mudanças no banco: crie a próxima migration (`010_...sql`), sem apagar dados, e aplique no Supabase.
3. Aumente `VERSAO` em `sw.js` para os celulares baixarem a versão nova.
4. Publicar = levar a branch para `main` (o GitHub Pages publica sozinho em 1 ou 2 minutos).
