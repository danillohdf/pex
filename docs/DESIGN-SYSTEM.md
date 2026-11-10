# PEX — Design system

Arquivo: `css/pex.css`. Sem bibliotecas de UI; tudo é CSS próprio com variáveis.

## Cores (cada uma tem uma função)
| Token | Uso |
|---|---|
| `--brand` / `--brand-700` | Marca, ação principal, item selecionado |
| `--brand-50` / `--brand-100` | Fundo de selecionado, destaque suave |
| `--surface`, `--surface-2`, `--surface-3` | Cartões, fundos de apoio, trilhos |
| `--bg` | Fundo geral (cinza muito claro) |
| `--ink`, `--ink-2`, `--muted`, `--faint` | Títulos, texto, apoio, placeholder |
| `--sun` | Destaque secundário (detalhe do logo) |
| `--bad` / `--bad-bg` | Crítico, risco, erro, bloqueio |
| `--warn` / `--warn-bg` | Alerta, pendência, atraso (laranja) |
| `--info` / `--info-bg` | Informação, estado neutro (azul) |
| `--ok` / `--ok-bg` | Conforme, concluído, aprovado |

Tema escuro automático pelo sistema; os mesmos tokens são redefinidos.

## Tipografia
Plus Jakarta Sans; números com `tabular-nums`; códigos em JetBrains Mono.
| Nível | Elemento | Tamanho |
|---|---|---|
| Título da página | `h1` (dentro de `.page-h`) | 22–28 px, 780 |
| Seção | `h2` | 18 px, 720 |
| Subtítulo | `h3` | 15 px, 700 |
| Texto | corpo | 14,5 px |
| Apoio | `.lead`, `.note` | 14,5 / 12,5 px, `--muted` |
| Rótulo de seção | `.sec-t`, `.grp-t`, `.eyebrow` | 11,5–12 px, maiúsculas |
| Indicador | `.kpi b`, `.idx` | 26–48 px |

## Forma e espaço
Raios `--r-xs 6` · `--r-sm 8` · `--r 10` (controles) · `--r-lg 14` (cartões). Espaços em múltiplos de 4 (`--s1`…`--s8`). Alturas: `--h-sm 34`, `--h 42`, `--h-lg 48` (com tela de toque: 38/46). Sombras: `--sh-1` (repouso), `--sh-2` (hover), `--sh-3` (sobreposições). Foco: `--ring` em todos os controles.

## Componentes
| Componente | Classe | Variações |
|---|---|---|
| Cabeçalho de página | `pageHead(título, descrição, ações)` → `.page-h` | — |
| Botão | `.btn` | `.pri` `.ghost` `.danger` `.danger.solid` `.sm` `.lg` `.block` `.icon` (com `data-tip`) |
| Campo | `input`, `select`, `textarea` dentro de `label.f` | `aria-invalid="true"` + `.f-err` |
| Busca | `.search` (ícone + input) | — |
| Barra de filtros | `.toolbar` | — |
| Alternador | `.segtog` | `aria-pressed` |
| Filtro rápido | `.chips` + `.chip` | `aria-pressed` |
| Abas internas | `.tabs-in` | `aria-selected` |
| Cartão | `.card` | `.flat` |
| Indicador | `.kpis` + `.kpi` | `.hero` `.ok` `.warn` `.bad` |
| Status | `.pill` | `.ok` `.warn` `.bad` `.info` `.brand` `.plain` |
| Alerta | `.banner` | `.ok` `.warn` `.bad` `.info` |
| Tabela | `.dt-wrap > table` | `tr.click`, `.th-sort` com `aria-sort`, `.sub` |
| Paginação | `.pager` | — |
| Progresso | `.pbar`, `.segbar`, `.meter` | — |
| Lista de cartões | `.vlist` (+ `.cols`) com `.vitem` / `.evc` | — |
| Estado vazio | `.empty` | — |
| Carregando | `.skel` | — |
| Seção recolhível | `details.fold` | `.rev` |
| Painel deslizante | `dialog.sheet` (`abrirSheet`) | — |
| Janela de diálogo | `dialog.modal` com `.modal-h/-b/-f` | — |
| Menu suspenso | `.menu` | — |
| Aviso | `toast(msg, tipo)` | `'ok'`, `'bad'` |

## Navegação
- **Computador (≥ 1024 px):** sidebar fixa de 252 px, recolhível para 72 px (preferência salva no aparelho), com dica ao passar o mouse quando recolhida.
- **Tablet (768–1023 px):** sidebar recolhida; o botão abre o menu por cima do conteúdo.
- **Celular (< 768 px):** barra superior com logo e perfil, mais a barra inferior com até 4 seções.
- Itens só de administração têm `data-admin` e são escondidos para o auditor; as permissões reais estão no banco (RLS).

## Regras
Sem gradientes decorativos, sem vidro fosco nos cartões, sem emojis no lugar de ícones, um único estilo de ícone (traço 1,9 px), cor só com significado funcional e animações curtas, desligadas com "reduzir movimento".
