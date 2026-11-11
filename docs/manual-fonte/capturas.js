const {chromium, devices} = require('playwright'); const path = require('path'); const fs = require('fs');
const {ctxFor} = require('./dash-shots.js'); const OUT = path.join(__dirname, 'manual'); const IMG = path.join(__dirname, 'amostra.jpg');
fs.mkdirSync(OUT, {recursive: true});
(async () => {
  const b = await chromium.launch(); const errs = [];
  const ctx = await ctxFor(b, {...devices['iPhone 13'], deviceScaleFactor: 2}); const p = await ctx.newPage(); p.setDefaultTimeout(15000); p.on('pageerror', e => errs.push(e.message));
  const w = ms => p.waitForTimeout(ms || 200);
  const semToast = () => p.evaluate(() => { const t = document.getElementById('toast'); if(t) t.hidden = true; });
  const shot = async n => { await w(250); await semToast(); await p.screenshot({path: `${OUT}/${n}.png`}); };
  const el = async (n, sel) => { const l = p.locator(sel).first(); await l.evaluate(e => e.scrollIntoView({block: 'center'})); await w(250); await semToast(); await l.screenshot({path: `${OUT}/${n}.png`}); };
  const topo = () => p.evaluate(() => window.scrollTo(0, 0));
  const criar = async (nome, email) => { await p.click('[data-act=auth-modo][data-v=criar]'); await p.fill('#a-nome', nome); await p.fill('#a-email', email); await p.fill('#a-senha', 'Senha@2026'); await p.click('#a-btn'); await w(500); };
  const entrar = async email => { await p.fill('#a-email', email); await p.fill('#a-senha', 'Senha@2026'); await p.click('#a-btn'); await p.waitForSelector('body.logado', {state: 'attached'}); await w(500); };
  const sair = async () => { if(await p.locator('#btn-conta').isVisible()){ await p.click('#btn-conta'); await p.click('#btn-sair'); } else await p.click('#main [data-act=sair]'); await p.waitForSelector('#f-auth'); };
  const todosC = async () => { for(let g=0; g<40; g++){ const l = p.locator('#step-body .item:not(.c):not(.nc):not(.na) button[data-act=res][data-v=c]'); if(!(await l.count())) break; await l.first().click(); await w(50); } };
  const fotosObr = async () => { for(let g=0; g<12; g++){ const keys = await p.$$eval('.req-i:not(.done) button[data-act=foto]', x => x.map(y => y.dataset.key)); if(!keys.length) break; const k = keys[0]; const n0 = await p.evaluate(k => document.querySelectorAll('[data-key="' + k + '"].x').length, k); await p.evaluate(k => { S.fotoKey = k; document.getElementById('file-in').value = ''; }, k); await p.setInputFiles('#file-in', IMG); await p.waitForFunction(([k, n0]) => document.querySelectorAll('[data-key="' + k + '"].x').length > n0, [k, n0]); await w(150); } };
  const nota = async (n, txt) => { await p.locator(`button[data-act=nota][data-v="${n}"]`).first().click(); await w(); await p.locator('textarea[data-b^="notas."]').first().fill(txt); };
  const prox = async () => { await p.click('#btn-prox'); await w(350); };

  // preparação (administração)
  await p.goto('http://pex.test/'); await p.waitForSelector('#f-auth');
  await criar('Danillo Henrique de Freitas', 'adm@pex.com'); await p.waitForSelector('body.logado', {state: 'attached'});
  await p.evaluate(() => go('usuarios')); await p.click('[data-act=cfg-tab][data-v=parques]'); await p.fill('#ev-lista', 'Dino World; GP1; Não\nElite; Helbert; Não\nFofíssimo; Helbert; Não\nNeve; GP5; Não'); await p.click('#btn-ev-add'); await w(500);
  await sair();
  // 1. acesso
  await shot('01-login');
  await p.click('[data-act=auth-modo][data-v=criar]'); await p.fill('#a-nome', 'Carla Souza Lima'); await p.fill('#a-email', 'carla@email.com'); await p.fill('#a-senha', 'Senha@2026'); await shot('02-criar');
  await p.click('#a-btn'); await w(600); await shot('03-aguardando');
  await p.click('#main [data-act=sair]'); await p.waitForSelector('#f-auth');
  await entrar('adm@pex.com'); await p.evaluate(() => go('usuarios')); await p.waitForSelector('.uitem.pend'); await p.click('.uitem.pend');
  await p.check('input[name=u-papel][value=auditor]'); await p.click('[data-act=usr-papel]'); await w(400); await p.click('#sheet [data-act=sheet-close]'); await sair();
  await entrar('carla@email.com'); await shot('04-painel-vazio');
  // 2. auditorias
  await p.click('.tabbar [data-v=visitas]'); await p.waitForSelector('#novo-ev'); await p.selectOption('#novo-ev', {label: 'Dino World'}); await shot('05-nova-auditoria');
  await p.click('#btn-novo'); await p.waitForSelector('[data-act=res]'); await topo(); await shot('06-editor-topo');
  await p.fill('#b-at-0', 'Maria Aparecida da Silva'); await p.click('[data-act=at-add]'); await w(); await p.fill('#b-at-1', 'Joana Pereira Lima');
  await el('07-quem-atendeu', '.card:has(#b-at-0)');
  await el('08-item-vazio', '#it-at-acolhimento');
  await todosC();
  await p.locator('#it-at-ticket button[data-v=nc]').click(); await w(); await p.fill('[data-b="itens.at-ticket.obs"]', 'Não ofereceu o combo de 2 horas, mesmo com 3 crianças.');
  await p.evaluate(() => { S.fotoKey = 'item:at-ticket'; document.getElementById('file-in').value = ''; }); await p.setInputFiles('#file-in', IMG); await p.waitForSelector('#it-at-ticket .ph img[src]'); await w(400);
  await el('09-item-nc', '#it-at-ticket');
  await p.click('#oc-from-at-ticket'); await w(300);
  await nota(4, 'Atendimento cordial e rápido; faltou oferecer combo maior.');
  await el('10-nota', '.nota');
  await el('11-rodape', '#foot-slot .foot');
  await prox();
  await topo(); await shot('12-identificacao');
  await p.click('#btn-ident'); await w(); await p.fill('#b-lider', 'Marcos Antônio'); await prox();
  await todosC(); await topo(); await shot('13-exposicao');
  await fotosObr(); await el('14-fotos-obrigatorias', '.req');
  await prox();
  await topo(); await shot('15-estoque');
  const n = await p.locator('[data-b$=".exposto"]').count();
  for(let i = 0; i < n; i++){ await p.fill(`[data-b="estoque.${i}.exposto"]`, String(10 + i)); await p.fill(`[data-b="estoque.${i}.reserva"]`, String(i * 3)); }
  await p.click('#btn-est-add'); await w(); await p.fill(`[data-b="estoque.${n}.sku"]`, 'Pelúcia'); await p.fill(`[data-b="estoque.${n}.exposto"]`, '4'); await p.fill(`[data-b="estoque.${n}.reserva"]`, '0');
  await p.locator('.sku').nth(1).scrollIntoViewIfNeeded(); await shot('16-estoque-contagem');
  await todosC(); await fotosObr(); await nota(4, 'Estoque organizado; caixas sem etiqueta na reserva.'); await prox();
  await todosC(); await fotosObr();
  await p.click('[data-act=ext-add][data-s=limpeza]'); await w(); await p.fill('#b-ext-limpeza-0', 'Cercado da entrada');
  await p.click('[data-act=ext-res][data-s=limpeza][data-v=nc]'); await w(); await p.fill('#b-ext-limpeza-0-obs', 'Poeira acumulada e adesivo descolando');
  await p.locator('#ext-limpeza-0 button[data-act=foto]').click(); await p.setInputFiles('#file-in', IMG); await p.waitForSelector('#ext-limpeza-0 .ph'); await w(400);
  await el('17-outro-local', '#ext-limpeza-0');
  await nota(3, 'Limpeza boa, exceto o cercado da entrada.'); await prox();
  await topo(); await shot('18-estrutura');
  await todosC(); await p.locator('#it-et-tuneis button[data-v=na]').click(); await w(); await p.fill('[data-b="itens.et-tuneis.obs"]', 'Este parque não tem túnel de fitas.');
  await el('19-item-na', '#it-et-tuneis');
  await nota(4, 'Estrutura firme; tatames bem presos.'); await prox();
  const oc = await p.locator('.oc').count();
  for(let i = 0; i < oc; i++){ await p.fill(`#b-oc-${i}-local`, i ? 'Cercado da entrada' : 'Balcão de atendimento'); if(!(await p.inputValue(`#b-oc-${i}-desc`))) await p.fill(`#b-oc-${i}-desc`, 'Descrição do problema'); }
  await topo(); await shot('20-ocorrencias');
  await prox(); await topo(); await shot('21-revisao');
  await p.locator('#btn-enviar').scrollIntoViewIfNeeded(); await shot('22-enviar');
  await p.click('#btn-enviar'); await w(700); await topo(); await shot('23-relatorio');
  await p.click('.tabbar [data-v=visitas]'); await w(400);
  // segunda auditoria em andamento para a lista
  await p.selectOption('#novo-ev', {label: 'Elite'}); await p.click('#btn-novo'); await p.waitForSelector('[data-act=res]'); await p.fill('#b-at-0', 'Ana Paula Rocha'); await w(1200); await p.click('#btn-fechar'); await w(400);
  await topo(); await shot('24-lista');
  // devolvida pela administração (simulado)
  await p.evaluate(() => { const db = JSON.parse(localStorage.getItem('fake:db')); const v = db.pex_visitas.find(x => x.data.enviadoEm); db.pex_validacoes.push({id: v.id, data: {status: 'devolvida', obs: 'Faltou a foto da recepção com o balcão inteiro. Refaça e reenvie.', em: Date.now(), por: 'adm'}, atualizado_em: new Date().toISOString()});
    const uid = JSON.parse(localStorage.getItem('fake:session')).user.id;
    db.pex_notificacoes = [{id: 1, usuario: uid, tipo: 'auditoria_devolvida', titulo: 'Auditoria devolvida para correção', texto: 'Dino World · Faltou a foto da recepção com o balcão inteiro.', alvo_tipo: 'visita', alvo_id: v.id, criada_em: new Date(Date.now() - 6e5).toISOString(), lida_em: null},
      {id: 2, usuario: uid, tipo: 'auditoria_enviada', titulo: 'Auditoria recebida', texto: 'Dino World · enviada para validação', alvo_tipo: null, criada_em: new Date(Date.now() - 864e5).toISOString(), lida_em: new Date().toISOString()}];
    localStorage.setItem('fake:db', JSON.stringify(db)); });
  await p.reload(); await p.waitForSelector('body.logado', {state: 'attached'}); await w(700);
  await p.evaluate(() => go('painel')); await w(500); await shot('25-painel');
  await p.click('.tabbar [data-v=visitas]'); await w(400); await p.locator('.vitem', {hasText: 'Dino World'}).first().evaluate(e => e.scrollIntoView({block: 'center'})); await shot('26-lista-devolvida');
  await p.click('.tabbar [data-act=tab][data-v=notificacoes], .tabbar [data-v=notificacoes]'); await w(400); await shot('27-avisos');
  await p.click('[data-act=notif-abrir][data-id="1"]'); await p.waitForSelector('[data-act=res]'); await w(400); await topo(); await shot('28-devolvida-editor');
  // sem internet
  await ctx.setOffline(true); await w(400); await p.locator('button[data-act=res][data-v=c]').first().click(); await w(1500);
  await el('29-indicador-offline', '.appbar'); await shot('30-offline');
  await ctx.setOffline(false); await w(2500); await el('31-indicador-online', '.appbar');
  await p.click('#btn-fechar'); await w(300);
  await p.click('#btn-conta'); await w(300); await shot('32-perfil');
  console.log('ERROS:', errs); await b.close();
})().catch(e => { console.error('FALHOU', String(e).slice(0, 500)); process.exit(1); });
