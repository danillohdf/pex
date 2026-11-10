# Fase 2 — Central de Pendências

## Banco (migration `supabase/005_central_pendencias.sql`, aplicada em 10/11/2026)
- `pex_acoes`: uma linha por ação corretiva (parque, auditoria e ocorrência de origem, item do checklist, problema, local, categoria, criticidade, departamento, responsável, ação necessária, prazo, status, fotos, evidências, observações). Código legível `AC-0001` pelo campo `numero`.
- `pex_acoes_hist`: histórico gravado só pelo banco (criação, cada campo alterado com valor anterior e novo, cada mudança de status com o texto, cada evidência).
- `pex_acao_transicao(id, para, texto, fotos)`: única forma de mudar o status.
  - Aberta/Reaberta → Em andamento ou Aguardando validação
  - Em andamento → Aguardando validação (exige descrição ou foto da correção)
  - Aguardando validação → Concluída (aprovar) ou Reaberta (rejeitar, motivo obrigatório)
  - Concluída → Reaberta (motivo obrigatório)
- `pex_acao_evidencia(id, texto, fotos)`: registra evidência sem mudar o status.
- RLS: só a administração lê e grava ações e histórico; não existe exclusão de ações; evidências não podem ser apagadas.
- A cópia inicial transformou cada ocorrência de auditoria já enviada em ação (status, prazo e responsável do plano antigo, quando havia). O plano antigo continua guardado em `pex_validacoes`.

## App
- Menu: **Central de Pendências** (só administração), com contador de ações atrasadas e aguardando validação.
- Indicadores clicáveis: atrasadas, críticas abertas, aguardando validação, abertas, em andamento e concluídas.
- Filtros: busca, parque, status, criticidade, departamento, responsável, auditoria de origem e período de identificação.
- Tabela ordenável e paginada (15 por página) no computador; cartões no celular.
- Detalhe da ação: andamento com os botões do fluxo, edição dos dados, fotos do problema, evidências, histórico com autor.
- Nova ação manual ou a partir de uma ocorrência (botão no relatório da auditoria, com parque, auditoria, item e fotos vinculados).
- Relatório da auditoria: cada ocorrência mostra a ação ligada (código, status, responsável, prazo) ou o botão para criá-la.
- Validação: o encerramento da auditoria e a situação "Bloqueado" passam a considerar as ações da Central.
