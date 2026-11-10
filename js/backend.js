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

  /* ---------- Coleções com tempo real ---------- */
  const colecoes = {};
  function colecao(nome){
    if(colecoes[nome]) return colecoes[nome];
    const tabela = TABELA[nome];
    const c = {nome, tabela, rows: new Map(), subs: [], carregado: false, canal: null, t: null};
    c.emit = () => { const docs = [...c.rows.entries()].map(([id, data]) => ({id, data: () => data})); c.subs.forEach(s => { try{ s.next({docs}); }catch(e){ console.error(e); } }); };
    c.recarregar = async () => {
      const all = new Map(); let from = 0; const page = 1000;
      for(;;){
        const {data, error} = await sb.from(tabela).select('id,data').order('id').range(from, from + page - 1);
        if(error){ c.subs.forEach(s => s.error && s.error(erro(error))); return; }
        data.forEach(r => all.set(r.id, r.data || {}));
        if(data.length < page) break; from += page;
      }
      c.rows = all; c.carregado = true; c.emit();
    };
    c.ligar = () => {
      if(c.canal) return;
      c.canal = sb.channel('pex-' + tabela)
        .on('postgres_changes', {event: '*', schema: 'public', table: tabela}, p => {
          if(p.eventType === 'DELETE'){ const id = p.old && p.old.id; if(id) c.rows.delete(id); }
          else if(p.new && p.new.id){ c.rows.set(p.new.id, p.new.data || {}); }
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
  function urlDe(caminho){
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
        const {error} = await sb.storage.from(BUCKET).upload(caminho, blob, {contentType: tipo, upsert: false, cacheControl: '31536000'});
        if(error) throw erro(error);
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
    const {data, error} = await sb.from('pex_perfis').select('id,nome,email,papel').eq('id', session.user.id).maybeSingle();
    if(error) throw erro(error);
    return data || {id: session.user.id, nome: '', email: session.user.email, papel: 'pendente'};
  }

  window.PEX = {
    configurado, sb, perfilAtual, rid, urlDe,
    runtime(perfil){ return {db, user: criarUser(perfil), assets: criarAssets(perfil)}; },
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
      async historico(id){ const {data, error} = await sb.from('pex_acoes_hist').select('*').eq('acao_id', id).order('id'); if(error) throw erroMsg(error); return data || []; },
      assinar(cb){ return sb.channel('pex-acoes').on('postgres_changes', {event: '*', schema: 'public', table: 'pex_acoes'}, p => cb(p)).subscribe(); }
    },
    async mudarPerfil(id, patch){ const {data, error} = await sb.from('pex_perfis').update(patch).eq('id', id).select('id'); if(error) throw erroMsg(error); if(!data.length) throw erro({code: '42501'}); }
  };
})();
