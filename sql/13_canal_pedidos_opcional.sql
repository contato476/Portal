-- ════════════════════════════════════════════════════════════════════
-- 13_CANAL_PEDIDOS_OPCIONAL.SQL
--
-- A aba "Pedir ajuste" no portal do cliente passa a ser OPCIONAL, e
-- nasce DESLIGADA.
--
-- POR QUÊ: hoje o cliente pede os ajustes na reunião e você anota.
-- Uma aba de pedidos visível, sem você acompanhar, seria pior que não
-- existir — o cliente escreveria num lugar que ninguém lê. Quando (e
-- se) fizer sentido, você liga em Projetos → aba Ajustes.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════

-- Guarda o estado do canal. 'off' = aba escondida no portal.
insert into public.app_settings (key, value)
values ('portal_pedidos_ativo', 'off')
on conflict (key) do nothing;


-- ──────────── PERMISSÃO DE LEITURA, SÓ DESSA CHAVE ────────────
-- app_settings é uma tabela sua: guarda o link secreto da agenda, o
-- link do Cal.com, a data da última sincronização. O cliente não pode
-- ver nada disso — mas precisa saber se a aba dele está ligada.
--
-- Por isso a policy é estreita de propósito: libera a leitura de UMA
-- chave, pelo nome. Qualquer outra continua invisível para ele.
drop policy if exists "cliente_le_flag_pedidos" on public.app_settings;
create policy "cliente_le_flag_pedidos" on public.app_settings
  for select to authenticated
  using (key = 'portal_pedidos_ativo');
