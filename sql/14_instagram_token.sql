-- ════════════════════════════════════════════════════════════════════
-- 14_INSTAGRAM_TOKEN.SQL
--
-- Prepara as chaves da integração do Instagram no app_settings.
--
-- POR QUE O TOKEN FICA NO BANCO E NÃO NUMA VARIÁVEL DA VERCEL:
-- o token da Meta vale 60 dias e pode ser RENOVADO por chamada. Mas a
-- Vercel não deixa uma função reescrever a própria variável de
-- ambiente — então, guardado lá, ele venceria a cada 2 meses e você
-- teria que refazer tudo à mão (e provavelmente descobriria só quando
-- as métricas parassem).
--
-- Guardado aqui, a função renova sozinha antes de vencer e você nunca
-- mais mexe nisso.
--
-- ESTA TABELA É SÓ SUA. A policy admin_all (sql/02) já garante que
-- ninguém além do admin lê. A única exceção é a chave
-- portal_pedidos_ativo, liberada de propósito no sql/13 — o token e o
-- resto continuam invisíveis para o cliente.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values
  ('ig_access_token',     null),   -- token de 60 dias, renovado sozinho
  ('ig_user_id',          null),   -- preenchido na primeira sincronização
  ('ig_username',         null),   -- só para mostrar "@seuperfil" na tela
  ('ig_token_expires_at', null),   -- quando vence, para avisar com folga
  ('ig_last_sync',        null)
on conflict (key) do nothing;


-- ──────────── CONFERÊNCIA ────────────
-- Rode esta consulta depois de conectar, para ver o estado da
-- integração. O token aparece só como "preenchido" ou "vazio" —
-- não faz sentido ficar exibindo o valor por aí.
--
-- select
--   key,
--   case when key = 'ig_access_token'
--        then case when value is null then 'vazio' else 'preenchido' end
--        else value end as valor
-- from public.app_settings
-- where key like 'ig_%'
-- order by key;
