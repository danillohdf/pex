/* Plataforma PEX · camada de dados sobre o Supabase.
   Expõe a mesma interface que o protótipo usava (db / user / assets),
   para que as telas continuem iguais. */
(function(){
  const cfg = window.PEX_CONFIG || {};
  const configurado = /^https:\/\/.+/.test(cfg.SUPABASE_URL || '') && !/SEU-PROJETO/.test(cfg.SUPABASE_URL) && cfg.SUPABASE_ANON_KEY && !/COLE-AQUI/.test(cfg.SUPABASE_ANON_KEY);
  const sb = configurado ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: {persistSession: true, autoRefreshToken: true, detectSessionInUrl: true}
  }) : null;

  const TABELA = {eventos: 'pex_eventos', visitas: 'pex_visitas', validacoes: 'pex_validacoes'};
  const BUCKET = 'pex-fotos';

  function erro(e){
    const err = new Error((e && e.message) || 'erro');
    const code = e && (e.code || e.statusCode || e.status);
    const msg = String((e && e.message) || '').toLowerCase();
    if(code === '42501' || /row-level security|permission denied/.test(msg)) err.code = 'invalid_argument';
    else if(String(code) === '413' || /too large|exceeded the maximum/.test(msg)) err.code = 'too_large';
    else if(String(code) === '415' || /mime type|invalid_mime/.test(msg)) err.code = 'unsupported_type';
    else if(String(code) === '429' || /rate limit/.test(msg)) err.code = 'rate_limited';
    else if(/quota|storage limit|exceeded/.test(msg)) err.code = 'quota_or_state';
    else err.code = 'network';
    return err;
  }

  // Mantém a mensagem escrita no banco (ex.: "Só o master gerencia administradores").
  function erroMsg(e){ const x = erro(e); if(e && e.message && (/[À-ú]|master|Sem permissão/.test(e.message) || ['22023','P0002'].includes(e.code))) x.message = e.message; return x; }

  function rid(n){ const a = new Uint8Array(n || 15); crypto.getRandomValues(a); return [...a].map(b => 'abcdefghijklmnopqrstuvwxyz0123456789'[b % 36]).join(''); }

  /* ---------- Offline: armazenamento local (IndexedDB) ----------
     cache:     última cópia de cada tabela (para abrir sem internet)
     fila:      alterações de auditorias ainda não enviadas (uma por auditoria, a mais recente)
     fotos:     fotos tiradas sem internet, enviadas na sincronização
     conflitos: cópia do servidor quando outro aparelho alterou a mesma auditoria */
  const IDB = (() => {
    let dbp = null;
    function abrir(){
      if(dbp) return dbp;
      dbp = new Promise((res, rej) => {
        if(!window.indexedDB) return rej(new Error('IndexedDB indisponível'));
        const r = indexedDB.open('pex-offline', 1);
        r.onupgradeneeded = () => { const d = r.result; ['cache', 'fila', 'fotos', 'conflitos'].forEach(n => { if(!d.objectStoreNames.contains(n)) d.createObjectStore(n); }); };
        r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
      });
      return dbp;
    }
    async function op(store, modo, fn){
      const d = await abrir();
      return new Promise((res, rej) => { const tx = d.transaction(store, modo); let out; const r = fn(tx.objectStore(store)); if(r) r.onsuccess = () => { out = r.result; }; tx.oncomplete = () => res(out); tx.onerror = () => rej(tx.error); tx.onabort = () => rej(tx.error); });
    }
    return {get: (st, k) => op(st, 'readonly', x => x.get(k)), put: (st, k, v) => op(st, 'readwrite', x => x.put(v, k)), del: (st, k) => op(st, 'readwrite', x => x.delete(k)), keys: st => op(st, 'readonly', x => x.getAllKeys())};
  })();
  const ehRede = e => !navigator.onLine || /failed to fetch|networkerror|network request|load failed|fetch failed|timeout/i.test(String((e && (e.message || e)) || ''));
  const net = {pendentes: 0, sinc: false, erro: null, ultimo: null, subs: [], remap: [], filaIds: new Set(), perfil: null, cadeia: Promise.resolve(), conflitos: 0};
  function estado(){ return {online: navigator.onLine, pendentes: net.filaIds.size, sincronizando: net.sinc, erro: net.erro, ultimo: net.ultimo, conflitos: net.conflitos}; }
  function avisar(){ net.subs.forEach(f => { try{ f(estado()); }catch(e){} }); }
  IDB.keys('fila').then(ks => { ks.forEach(k => net.filaIds.add(k)); avisar(); }).catch(() => {});
  addEventListener('online', () => { avisar(); sincronizar(); });
  addEventListener('offline', avisar);
  setInterval(() => { if(navigator.onLine && net.filaIds.size && !net.sinc) sincronizar(); }, 30000);

  /* ---------- Coleções com tempo real ---------- */
  const colecoes = {};
  function colecao(nome){
    if(colecoes[nome]) return colecoes[nome];
    const tabela = TABELA[nome];
    const c = {nome, tabela, rows: new Map(), meta: new Map(), subs: [], carregado: false, canal: null, t: null};
    c.emit = () => { const docs = [...c.rows.entries()].map(([id, data]) => ({id, data: () => data})); c.subs.forEach(s => { try{ s.next({docs}); }catch(e){ console.error(e); } }); };
    c.recarregar = async () => {
      const all = new Map(); let from = 0; const page = 1000;
      for(;;){
        const {data, error} = await sb.from(tabela).select('id,data,atualizado_em').order('id').range(from, from + page - 1);
        if(error){
          if(ehRede(error)){ // sem internet: usa a última cópia guardada no aparelho
            if(!c.carregado){ const cache = await IDB.get('cache', tabela).catch(() => null); if(cache){ c.rows = new Map(cache.rows); c.meta = new Map(cache.meta || []); } await aplicarFila(c); c.carregado = true; c.emit(); }
            return;
          }
          c.subs.forEach(s => s.error && s.error(erro(error))); return;
        }
        data.forEach(r => { all.set(r.id, r.data || {}); c.meta.set(r.id, r.atualizado_em); });
        if(data.length < page) break; from += page;
      }
      c.rows = all; IDB.put('cache', tabela, {rows: [...all], meta: [...c.meta], em: Date.now()}).catch(() => {});
      await aplicarFila(c); c.carregado = true; c.emit();
    };
    c.ligar = () => {
      if(c.canal) return;
      c.canal = sb.channel('pex-' + tabela)
        .on('postgres_changes', {event: '*', schema: 'public', table: tabela}, p => {
          if(p.eventType === 'DELETE'){ const id = p.old && p.old.id; if(id) c.rows.delete(id); }
          else if(p.new && p.new.id && !(c.nome === 'visitas' && net.filaIds.has(p.new.id))){ c.rows.set(p.new.id, p.new.data || {}); if(p.new.atualizado_em) c.meta.set(p.new.id, p.new.atualizado_em); }
          clearTimeout(c.t); c.t = setTimeout(c.emit, 60);
        })
        .subscribe(st => { if(st === 'SUBSCRIBED' && c.carregado) c.recarregar(); });
    };
    colecoes[nome] = c;
    return c;
  }
  // Ao voltar para o app (celular em segundo plano derruba a conexão), recarrega tudo.
  document.addEventListener('visibilitychange', () => { if(document.visibilityState === 'visible') Object.values(colecoes).forEach(c => c.carregado && c.recarregar()); });
  window.addEventListener('online', () => Object.values(colecoes).forEach(c => c.carregado && c.recarregar()));

  function docRef(nome, id){
    const c = colecao(nome);
    return {
      id,
      async set(data){
        if(c.nome === 'visitas') return salvarVisita(c, id, data);
        const existe = c.rows.has(id);
        const q = existe ? sb.from(c.tabela).update({data}).eq('id', id).select('id,data') : sb.from(c.tabela).insert({id, data}).select('id,data');
        let {data: out, error} = await q;
        // Se outro aparelho criou o registro antes do tempo real chegar, tenta como atualização.
        if(error && error.code === '23505'){ ({data: out, error} = await sb.from(c.tabela).update({data}).eq('id', id).select('id,data')); }
        if(error) throw erro(error);
        if(!out || !out.length) throw erro({code: '42501', message: 'permission denied'});
        c.rows.set(id, out[0].data || data); c.emit();
      },
      async update(patch){
        const atual = c.rows.get(id) || {};
        const data = {...atual, ...patch};
        const {data: out, error} = await sb.from(c.tabela).update({data}).eq('id', id).select('id,data');
        if(error) throw erro(error);
        if(!out || !out.length) throw erro({code: '42501', message: 'permission denied'});
        c.rows.set(id, out[0].data); c.emit();
      },
      async delete(){
        const {error} = await sb.from(c.tabela).delete().eq('id', id);
        if(error) throw erro(error);
        c.rows.delete(id); c.emit();
      }
    };
  }

  async function aplicarFila(c){
    if(c.nome !== 'visitas' || !net.filaIds.size) return;
    for(const id of net.filaIds){ const e = await IDB.get('fila', id).catch(() => null); if(e) c.rows.set(id, e.data); }
  }
  async function salvarVisita(c, id, data){
    let guardou = true;
    try{ const ant = await IDB.get('fila', id); await IDB.put('fila', id, {id, data, base: ant ? ant.base : (c.meta.get(id) || null), em: Date.now()}); net.filaIds.add(id); }
    catch(e){ guardou = false; }
    c.rows.set(id, data); c.emit(); avisar();
    if(!guardou) return gravarVisitaDireto(c, id, data).then(() => ({sincronizado: true}));
    const r = await sincronizarUm(id);
    if(r === true) return {sincronizado: true};
    if(r && !r.rede){
      // envio recusado pelo banco (auditoria incompleta): a cópia local volta a ser rascunho
      if(data && data.enviadoEm && /Auditoria incompleta/.test((r.erro && r.erro.message) || '')){
        const rasc = {...data, enviadoEm: null}; c.rows.set(id, rasc); c.emit();
        const at = await IDB.get('fila', id).catch(() => null); if(at) await IDB.put('fila', id, {...at, data: rasc}).catch(() => {});
        net.erro = null; avisar(); sincronizarUm(id);
      }
      throw r.erro;
    }
    return {pendente: true};
  }
  async function gravarVisitaDireto(c, id, data){
    let {data: out, error} = await sb.from(c.tabela).update({data}).eq('id', id).select('id,data,atualizado_em');
    if(!error && (!out || !out.length)){
      // auditoria que ainda não existe no servidor (criada sem internet): entra como rascunho e, se já foi enviada, é enviada em seguida
      const rasc = data && data.enviadoEm ? {...data, enviadoEm: null} : data;
      ({data: out, error} = await sb.from(c.tabela).insert({id, data: rasc}).select('id,data,atualizado_em'));
      if(error && error.code === '23505') throw erro({code: '42501', message: 'permission denied'});
      if(!error && rasc !== data) ({data: out, error} = await sb.from(c.tabela).update({data}).eq('id', id).select('id,data,atualizado_em'));
    }
    if(error) throw Object.assign(erroMsg(error), {original: error});
    if(!out || !out.length) throw erro({code: '42501', message: 'permission denied'});
    return out[0];
  }
  function trocarIds(x, mapa){ if(typeof x === 'string') return mapa[x] || x; if(Array.isArray(x)) return x.map(y => trocarIds(y, mapa)); if(x && typeof x === 'object'){ const o = {}; for(const k in x) o[k] = trocarIds(x[k], mapa); return o; } return x; }
  function idsLocais(x, out){ if(typeof x === 'string'){ if(x.startsWith('local:')) out.add(x); } else if(Array.isArray(x)) x.forEach(y => idsLocais(y, out)); else if(x && typeof x === 'object') Object.values(x).forEach(y => idsLocais(y, out)); return out; }
  // Envia uma auditoria da fila. Uma por vez, em ordem, para não duplicar nem cruzar versões.
  function sincronizarUm(id){
    const tarefa = net.cadeia.then(async () => {
      const c = colecao('visitas'); const e = await IDB.get('fila', id).catch(() => null);
      if(!e){ net.filaIds.delete(id); return true; }
      if(!navigator.onLine) return {rede: true};
      net.sinc = true; avisar();
      try{
        // 1) fotos tiradas sem internet
        const locais = [...idsLocais(e.data, new Set())]; const mapa = {};
        for(const lid of locais){
          const f = await IDB.get('fotos', lid).catch(() => null); if(!f) continue;
          const caminho = `${(net.perfil || {}).id}/${new Date().toISOString().slice(0,10)}/${lid.slice(6)}.${f.tipo === 'image/png' ? 'png' : f.tipo === 'image/webp' ? 'webp' : 'jpg'}`;
          const {error} = await sb.storage.from(BUCKET).upload(caminho, f.blob, {contentType: f.tipo, upsert: true, cacheControl: '31536000'});
          if(error) throw Object.assign(erro(error), {original: error});
          mapa[lid] = caminho;
        }
        let data = locais.length ? trocarIds(e.data, mapa) : e.data;
        // 2) conflito: o servidor mudou desde a última versão que este aparelho conhecia?
        if(e.base){
          const {data: srv} = await sb.from(c.tabela).select('data,atualizado_em').eq('id', id).maybeSingle();
          if(srv && srv.atualizado_em && new Date(srv.atualizado_em) > new Date(e.base)){
            await IDB.put('conflitos', id + ':' + Date.now(), {id, servidor: srv.data, em: Date.now()}).catch(() => {});
            net.conflitos++;
          }
        }
        // 3) grava
        const row = await gravarVisitaDireto(c, id, data);
        const atual = await IDB.get('fila', id).catch(() => null);
        if(atual && atual.em === e.em){ await IDB.del('fila', id); net.filaIds.delete(id); }
        else if(atual && locais.length){ await IDB.put('fila', id, {...atual, data: trocarIds(atual.data, mapa), base: row.atualizado_em}); }
        if(!net.filaIds.has(id)) c.rows.set(id, row.data);
        c.meta.set(id, row.atualizado_em);
        for(const lid of locais) IDB.del('fotos', lid).catch(() => {});
        if(locais.length) net.remap.forEach(f => { try{ f(id, mapa); }catch(x){} });
        net.erro = null; net.ultimo = Date.now(); c.emit();
        return true;
      }catch(err){
        const rede = ehRede(err.original || err);
        if(!rede) net.erro = err.message || 'Erro de sincronização';
        return {rede, erro: err};
      }finally{ net.sinc = false; avisar(); }
    });
    net.cadeia = tarefa.catch(() => {});
    return tarefa;
  }
  async function sincronizar(){
    if(!navigator.onLine) return estado();
    const ids = await IDB.keys('fila').catch(() => []); ids.forEach(k => net.filaIds.add(k));
    for(const id of ids){ const r = await sincronizarUm(id); if(r && r.rede) break; }
    return estado();
  }

  const db = {
    collection(nome){
      return {
        doc(id){ return docRef(nome, id || rid(20)); },
        onSnapshot(next, error){
          const c = colecao(nome); const sub = {next, error}; c.subs.push(sub);
          if(c.carregado) setTimeout(() => next({docs: [...c.rows.entries()].map(([id, data]) => ({id, data: () => data}))}), 0);
          else { c.ligar(); c.recarregar(); }
          return () => { c.subs = c.subs.filter(s => s !== sub); };
        }
      };
    },
    doc(path){ const [nome, id] = path.split('/'); return docRef(nome, id); }
  };

  /* ---------- Usuário ---------- */
  function criarUser(perfil){
    return {
      async me(){ return {id: perfil.id, canEdit: perfil.papel === 'admin' || perfil.papel === 'master', name: perfil.nome}; },
      async can(){ return ['auditor','admin','master'].includes(perfil.papel); },
      async profiles(ids){
        const out = {};
        const {data} = await sb.from('pex_perfis').select('id,nome').in('id', ids);
        (data || []).forEach(p => { out[p.id] = {id: p.id, name: p.nome, isMe: p.id === perfil.id}; });
        return out;
      }
    };
  }

  /* ---------- Fotos ---------- */
  const urls = new Map(); // caminho -> {url, ate}
  const espera = new Map();
  let fila = new Set(), filaT = null;
  function pedirUrls(){
    const caminhos = [...fila]; fila = new Set(); filaT = null;
    if(!caminhos.length) return;
    sb.storage.from(BUCKET).createSignedUrls(caminhos, 3600).then(({data}) => {
      (data || []).forEach(r => { if(r.signedUrl){ urls.set(r.path, {url: r.signedUrl, ate: Date.now() + 3300e3}); } const w = espera.get(r.path); if(w){ w.forEach(f => f(r.signedUrl || '')); espera.delete(r.path); } });
      caminhos.forEach(p => { const w = espera.get(p); if(w){ w.forEach(f => f('')); espera.delete(p); } });
    }).catch(() => caminhos.forEach(p => { const w = espera.get(p); if(w){ w.forEach(f => f('')); espera.delete(p); } }));
  }
  const urlsLocais = new Map();
  function urlDe(caminho){
    if(String(caminho).startsWith('local:')){
      if(urlsLocais.has(caminho)) return Promise.resolve(urlsLocais.get(caminho));
      return IDB.get('fotos', caminho).then(f => { if(!f) return ''; const u = URL.createObjectURL(f.blob); urlsLocais.set(caminho, u); return u; }).catch(() => '');
    }
    const c = urls.get(caminho);
    if(c && c.ate > Date.now()) return Promise.resolve(c.url);
    return new Promise(res => {
      if(!espera.has(caminho)) espera.set(caminho, []);
      espera.get(caminho).push(res);
      fila.add(caminho);
      if(!filaT) filaT = setTimeout(pedirUrls, 30);
    });
  }
  function criarAssets(perfil){
    return {
      async upload(blob, opts){
        const tipo = (opts && opts.type) || blob.type || 'image/jpeg';
        const ext = tipo === 'image/png' ? 'png' : tipo === 'image/webp' ? 'webp' : 'jpg';
        const caminho = `${perfil.id}/${new Date().toISOString().slice(0,10)}/${rid(16)}.${ext}`;
        const guardarLocal = async () => { const lid = 'local:' + rid(16); await IDB.put('fotos', lid, {blob, tipo, em: Date.now()}); return {id: lid, local: true}; };
        if(!navigator.onLine) return guardarLocal();
        const {error} = await sb.storage.from(BUCKET).upload(caminho, blob, {contentType: tipo, upsert: false, cacheControl: '31536000'});
        if(error){ if(ehRede(error)) return guardarLocal(); throw erro(error); }
        return {id: caminho};
      },
      url: urlDe
    };
  }

  // Preenche sozinho o src de toda <img data-fid> que aparecer na tela.
  function hidratar(raiz){
    (raiz.querySelectorAll ? raiz : document).querySelectorAll('img[data-fid]:not([src])').forEach(img => {
      if(img.dataset.pedido) return; img.dataset.pedido = '1';
      urlDe(img.dataset.fid).then(u => { if(u) img.src = u; else img.alt = 'Foto indisponível'; });
    });
  }
  new MutationObserver(ms => { for(const m of ms) m.addedNodes.forEach(n => n.nodeType === 1 && (n.matches && n.matches('img[data-fid]') ? hidratar(n.parentNode) : hidratar(n))); })
    .observe(document.documentElement, {childList: true, subtree: true});

  /* ---------- Sessão ---------- */
  async function perfilAtual(){
    const {data: {session}} = await sb.auth.getSession();
    if(!session) return null;
    const chave = 'pex-perfil:' + session.user.id;
    const {data, error} = await sb.from('pex_perfis').select('id,nome,email,papel').eq('id', session.user.id).maybeSingle();
    if(error){
      if(ehRede(error)){ try{ const p = JSON.parse(localStorage.getItem(chave) || 'null'); if(p) return p; }catch(e){} }
      throw erro(error);
    }
    const p = data || {id: session.user.id, nome: '', email: session.user.email, papel: 'pendente'};
    try{ localStorage.setItem(chave, JSON.stringify(p)); }catch(e){}
    return p;
  }

  window.PEX = {
    configurado, sb, perfilAtual, rid, urlDe,
    runtime(perfil){ net.perfil = perfil; setTimeout(sincronizar, 500); return {db, user: criarUser(perfil), assets: criarAssets(perfil)}; },
    offline: {estado, assinar(f){ net.subs.push(f); f(estado()); }, sincronizar, aoRemapear(f){ net.remap.push(f); }},
    async entrar(email, senha){ const {error} = await sb.auth.signInWithPassword({email, password: senha}); if(error) throw error; },
    async cadastrar(nome, email, senha){
      const {data, error} = await sb.auth.signUp({email, password: senha, options: {data: {nome}, emailRedirectTo: location.origin + location.pathname}});
      if(error) throw error; return data;
    },
    async recuperar(email){ const {error} = await sb.auth.resetPasswordForEmail(email, {redirectTo: location.origin + location.pathname}); if(error) throw error; },
    async novaSenha(senha){ const {error} = await sb.auth.updateUser({password: senha}); if(error) throw error; },
    async sair(){ await sb.auth.signOut(); },
    async perfis(){ const {data, error} = await sb.from('pex_perfis').select('id,nome,email,papel,criado_em').order('criado_em'); if(error) throw erro(error); return data; },
    async listaUsuarios(){ const {data, error} = await sb.rpc('pex_lista_usuarios'); if(error) throw erroMsg(error); return data || []; },
    async excluirUsuario(id){ const {error} = await sb.rpc('pex_excluir_usuario', {alvo: id}); if(error) throw erroMsg(error); },
    async definirSenha(id, senha){ const {error} = await sb.rpc('pex_definir_senha', {alvo: id, senha}); if(error) throw erroMsg(error); },
    async confirmarEmail(id){ const {error} = await sb.rpc('pex_confirmar_email', {alvo: id}); if(error) throw erroMsg(error); },
    /* Central de Pendências: ações corretivas (tabela pex_acoes, só administração) */
    acoes: {
      async listar(){
        const out = []; let from = 0; const page = 1000;
        for(;;){
          const {data, error} = await sb.from('pex_acoes').select('*').order('numero').range(from, from + page - 1);
          if(error) throw erroMsg(error);
          out.push(...data); if(data.length < page) break; from += page;
        }
        return out;
      },
      async criar(obj){ const {data, error} = await sb.from('pex_acoes').insert(obj).select('*'); if(error) throw erroMsg(error); return data[0]; },
      async atualizar(id, patch){ const {data, error} = await sb.from('pex_acoes').update(patch).eq('id', id).select('*'); if(error) throw erroMsg(error); if(!data || !data.length) throw erro({code: '42501'}); return data[0]; },
      async transicao(id, para, texto, fotos){ const {data, error} = await sb.rpc('pex_acao_transicao', {p_id: id, p_para: para, p_texto: texto || '', p_fotos: fotos || []}); if(error) throw erroMsg(error); return Array.isArray(data) ? data[0] : data; },
      async evidencia(id, texto, fotos){ const {data, error} = await sb.rpc('pex_acao_evidencia', {p_id: id, p_texto: texto || '', p_fotos: fotos || []}); if(error) throw erroMsg(error); return Array.isArray(data) ? data[0] : data; },
      async historicoVarios(ids){ const out = []; for(let i = 0; i < ids.length; i += 100){ const {data, error} = await sb.from('pex_acoes_hist').select('*').in('acao_id', ids.slice(i, i + 100)).order('id'); if(error) throw erroMsg(error); out.push(...(data || [])); } return out; },
      async historico(id){ const {data, error} = await sb.from('pex_acoes_hist').select('*').eq('acao_id', id).order('id'); if(error) throw erroMsg(error); return data || []; },
      assinar(cb){ return sb.channel('pex-acoes').on('postgres_changes', {event: '*', schema: 'public', table: 'pex_acoes'}, p => cb(p)).subscribe(); }
    },
    /* Notificações internas (pex_notificacoes, só as do próprio usuário) */
    notif: {
      async listar(){ const {data, error} = await sb.from('pex_notificacoes').select('*').order('criada_em', {ascending: false}).limit(150); if(error) throw erroMsg(error); return data || []; },
      async marcar(ids){ const {error} = await sb.rpc('pex_notif_lidas', {p_ids: ids || null}); if(error) throw erroMsg(error); },
      async prazos(){ const {error} = await sb.rpc('pex_verificar_prazos'); if(error) throw erroMsg(error); },
      assinar(uid, cb){ return sb.channel('pex-notif').on('postgres_changes', {event: 'INSERT', schema: 'public', table: 'pex_notificacoes', filter: 'usuario=eq.' + uid}, p => cb(p.new)).subscribe(); }
    },
    async mudarPerfil(id, patch){ const {data, error} = await sb.from('pex_perfis').update(patch).eq('id', id).select('id'); if(error) throw erroMsg(error); if(!data.length) throw erro({code: '42501'}); }
  };
})();
