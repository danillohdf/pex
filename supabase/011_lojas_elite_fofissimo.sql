-- =====================================================================
-- Plataforma PEX · novas lojas auditadas: Elite e Fofíssimo (sócio Helbert)
-- Só acrescenta; se já existirem, não mexe nelas.
-- =====================================================================
insert into public.pex_eventos(id, data) values
('elite',     '{"nome": "Elite",      "franquia": "Helbert", "inflaveis": null, "ordem": 44}'::jsonb),
('fofissimo', '{"nome": "Fofíssimo",  "franquia": "Helbert", "inflaveis": null, "ordem": 45}'::jsonb)
on conflict (id) do nothing;
