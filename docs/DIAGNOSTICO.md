# PEX — Diagnóstico técnico (início do PEX 2.0)

Data: 10/11/2026 · Branch de trabalho: `pex-2.0` · Base: `main` @ `2ca5719`

## 1. Arquitetura atual

| Camada | Como é hoje |
|---|---|
| Frontend | Um único `index.html` (~147 KB): CSS inline, HTML da casca e todo o JavaScript da aplicação (vanilla JS, sem build). As telas são *template strings* renderizadas em `#main`. |
| Estado | Objeto global `S` (`eventos`, `visitas`, `val`, `tab`, `edit`, `rep`, `me`, `perfil`…). |
| Roteamento | Hash (`#painel`, `#visitas`, `#validacao`, `#usuarios`) → `route()` → `render()`. O editor da visita (`S.edit`) e o relatório (`S.rep`) são estados sobrepostos à aba. |
| Dados | `js/backend.js` emula uma API de documentos (`db.collection().onSnapshot`, `doc().set/update`) sobre tabelas do Supabase com uma coluna `data jsonb`. Tempo real via `postgres_changes`; recarrega ao voltar o foco ou a conexão. |
| Fotos | Bucket privado `pex-fotos`; caminho `{uid}/{data}/{id}.jpg`; leitura por URL assinada (1 h) com cache; compressão para 1600 px no navegador antes do envio. |
| Login | Supabase Auth (e-mail e senha). "Confirm email" desligado. |
| PWA | `manifest.webmanifest` + `sw.js` (cache da casca, rede primeiro). **Não há persistência offline dos dados**: sem sinal, as respostas ficam só na memória da aba. |
| Publicação | GitHub Pages da `main` (`danillohdf.github.io/pex`). O site antigo na Netlify continua no ar com uma versão anterior (`pex-v6`). |
| Bibliotecas | Somente `@supabase/supabase-js` 2.45.4, vendorizada em `js/supabase.min.js`. Fontes do Google. |

### Mapa do `index.html`
Protocolo (etapas, itens, escalas) · Estado · Cálculos (índice, situação, reincidência) · Inicialização e sessão · Rotas · Painel · Visitas · Editor da visita (8 etapas) · Fotos · Relatório e validação · Fila de validação · Eventos de interface · Login · Usuários · Cadastro de parques · Ícones e painel deslizante · Colaboradora, estoque declarado, outros locais e revisão.

## 2. Banco de dados (Supabase `plataforma-pex`, sa-east-1)

| Tabela | Linhas | Conteúdo |
|---|---|---|
| `pex_perfis` | 2 | Perfil do usuário: `nome`, `email`, `papel` (`pendente`, `auditor`, `admin`, `master`, `bloqueado`). |
| `pex_eventos` | 43 | Parques: `data = {nome, franquia (= sócio), inflaveis, ordem}`. |
| `pex_visitas` | 1 | Auditoria inteira em `data` (itens, notas, fotos, estoque, ocorrências, atendentes, extras, datas). Coluna `auditor` protegida por gatilho. |
| `pex_validacoes` | 1 | Validação da administração em `data`: `status`, `hist`, `obs`, conferências das áreas, **plano de ação** em `acoes[idOcorrencia] = {resp, prazo, status, obs, fotos}`, `teorico[]`. |

Migrations versionadas: `supabase/001_schema.sql` … `004_hierarquia.sql`.

### Funções e gatilhos
`pex_papel/ativo/admin/master` (papel de quem está logado) · `pex_visita_editavel` (o auditor só edita rascunho ou visita devolvida) · `pex_visita_guard` (o auditor da visita não muda) · `pex_perfil_guard` (hierarquia de papéis) · `pex_novo_usuario` (cria o perfil no cadastro) · RPCs do master: `pex_lista_usuarios`, `pex_excluir_usuario`, `pex_definir_senha`, `pex_confirmar_email`.

### RLS (verificada no banco real em 10/11)
| Tabela | Leitura | Escrita |
|---|---|---|
| perfis | o próprio ou admin | admin (com a hierarquia do gatilho) |
| eventos | auditor e admin | admin |
| visitas | admin vê todas; auditor só as dele | auditor cria e edita as dele enquanto editável; admin apaga |
| validações | admin; auditor só das próprias visitas | admin |
| fotos | admin; auditor só a própria pasta | envio só na própria pasta; admin apaga |

O teste de 10/11 confirmou o isolamento entre auditores e as recusas de escalada de privilégio.

## 3. Perfis
- **Auditor**: Meu painel, Visitas (só as dele), relatório das próprias visitas.
- **Administração** (`admin`): tudo + Validação, Usuários (libera e bloqueia auditores), cadastro de parques.
- **Master** (`master`, único): Administração + promover e remover administradores, excluir logins, senha provisória. Para o PEX 2.0 o master continua sendo "Administração" com poderes extras de gestão de acesso; não é um terceiro perfil operacional.
- `pendente` e `bloqueado` são estados de acesso, não perfis.

## 4. Fluxos existentes
**Auditoria (8 etapas):** Cliente oculto (com nome completo de quem atendeu) → Identificação → Exposição → Estoque (contagem declarada) → Limpeza → Estrutura → Ocorrências → Enviar (revisão e regras de aceite). Salvamento automático a cada alteração.

**Validação:** Aguardando validação → Em validação → (Devolvida | Ação corretiva) → Validado (conferências de Compras, Operações e Manutenção) → Encerrado (todas as ocorrências resolvidas). Situação do parque: Em análise / Aprovado (≥ 3 e sem crítica) / Reprovado / Bloqueado (crítica aberta).

**Ocorrências e ações hoje:** a ocorrência nasce dentro da visita (do item não conforme ou de um "outro local"). O plano de ação (responsável, prazo, status, evidência) fica dentro do documento de validação. Existe a lista "Plano de ação em aberto" na aba Validação.

## 5. Pontos fracos e riscos encontrados
| # | Problema | Impacto | Onde resolver |
|---|---|---|---|
| 1 | Ações corretivas vivem dentro do JSON da validação: sem histórico por ação, sem departamento separado do responsável, sem "aguardando validação/reaberta", difícil de filtrar e consultar | Central de Pendências inviável sem estrutura própria | Fase 2: tabela `pex_acoes` + `pex_acoes_hist`, cópia não destrutiva das ações atuais |
| 2 | Não conformidade sem ocorrência some do acompanhamento | Problemas não cobrados | Fase 3 |
| 3 | Salvar a visita regrava o documento inteiro (última gravação vence), sem número de versão | Risco de sobrescrita com dois aparelhos ou sincronização offline | Fase 6: coluna de versão + resolução de conflito |
| 4 | Sem persistência local dos dados | Perda de respostas se o app fechar sem sinal | Fase 6: IndexedDB + fila de sincronização |
| 5 | O banco não valida a completude no envio (regras de aceite só no app) | Envio incompleto por chamada direta | Fase 7: função de envio no banco |
| 6 | Gatilho de cadastro: "o primeiro usuário vira master" ainda existe (inofensivo hoje, porque já há master) | Se o master for removido, o próximo cadastro vira master | Fase 7: remover o bootstrap automático |
| 7 | Toda a base de visitas é carregada na abertura | Fica pesado com centenas de auditorias | Fase 4/5: consultas agregadas e paginação |
| 8 | `index.html` com tudo junto | Manutenção difícil | Contínuo: CSS separado já na Fase 1; JS separado por módulos ao longo das fases |
| 9 | Site antigo da Netlify ainda no ar | Auditor pode usar versão velha | Decisão do dono: desativar |
| 10 | Fotos de usuários excluídos permanecem no bucket | Espaço | Fase 7 (decisão: manter como histórico) |

## 6. Plano de execução (resumo)
1. **Design system e navegação** — CSS em arquivo próprio, tokens e componentes, sidebar recolhível, padrão de página. Sem mudança de banco.
2. **Central de Pendências** — `pex_acoes` e histórico, departamentos, responsáveis, prazos, status com validação da correção. Migração não destrutiva.
3. **Integração** — não conforme → ação (ou justificativa obrigatória).
4. **Dashboard executivo** — KPIs, ranking, mapa de calor, departamentos, reincidência, evolução.
5. **Parques, histórico e PDFs.**
6. **Notificações e offline real.**
7. **Revisão final, segurança e documentação.**

Toda mudança de banco: migration SQL nova em `supabase/`, testada antes num Postgres local, aplicada ao projeto real só com autorização.
