# Segurança · Plataforma PEX 2.0

## Como os dados são protegidos

- **Regras no banco (RLS)** em todas as tabelas: auditor só lê e altera o que é dele; administração e master veem tudo. As telas escondem botões, mas quem barra de verdade é o banco.
- **Fotos** ficam num bucket privado (`pex-fotos`) e só são abertas por links temporários. O auditor só vê as fotos da própria pasta.
- **Ações e status** só mudam pelas funções do fluxo (`pex_acao_transicao`, `pex_acao_evidencia`), que conferem o papel de quem chama e gravam histórico. Ações nunca são apagadas.
- **Validação**: uma auditoria não é validada com não conformidade sem ação ou justificativa, nem encerrada com ação aberta (trigger `pex_validacao_guard`).
- **Envio da auditoria** (008): o banco recusa envio sem parque, identificação ao líder, quem atendeu, respostas, notas com justificativa ou ocorrências completas (crítica precisa ter sido comunicada). Rascunhos salvam livremente.
- **Notificações**: cada pessoa só lê as próprias; ninguém cria ou altera notificação pelo app.
- **Chaves**: o app só tem a chave pública (anon). Nenhuma chave privada está no código.

## Primeiro usuário master (bootstrap)

Até a 2.0, se não existisse nenhum admin/master, o próximo cadastro público virava master. Isso foi removido na migration 008: **todo cadastro novo entra como pendente**.

Para nomear um master numa instalação nova (ou recuperar o acesso), alguém com acesso ao painel do Supabase roda no **SQL Editor**:

```sql
update public.pex_perfis set papel = 'master' where email = 'email-da-pessoa@exemplo.com';
```

A pessoa precisa ter criado o acesso no app antes. O app nunca consegue fazer isso sozinho: a trava `pex_perfil_guard` só permite essa mudança fora do app.

## Funções que o app chama (avisos do Supabase)

O painel do Supabase lista 14 funções "SECURITY DEFINER" que usuários logados podem chamar. Isso é intencional: são as funções do próprio app, e cada uma confere o papel de quem chama. Foi testado no banco real com um auditor comum:

| Função | Resultado com auditor |
|---|---|
| `pex_confirmar_email`, `pex_definir_senha`, `pex_excluir_usuario` | Recusado ("Sem permissão" / "Só o master…") |
| `pex_acao_transicao`, `pex_acao_evidencia` | Recusado ("Só a administração…") |
| `pex_lista_usuarios`, `pex_nc_pendentes`, `pex_verificar_prazos` | Não devolve nada |
| `pex_papel`, `pex_ativo`, `pex_admin`, `pex_master`, `pex_visita_editavel` | Só respondem sobre o próprio usuário (usadas pelas regras de acesso) |
| `pex_notif_lidas` | Só marca as notificações do próprio usuário |

## Configurações do painel do Supabase

- **Leaked password protection** (bloquear senhas vazadas): só existe nos planos pagos (Pro em diante). No plano gratuito fica desligado; o Supabase recusa ativar.
- Token do Netlify: o site `pex-eventokids` foi apagado em 11/11/2026. O token pessoal usado na publicação antiga foi revogado.
