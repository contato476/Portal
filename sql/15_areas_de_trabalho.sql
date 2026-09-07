-- ════════════════════════════════════════════════════════════════════
-- 15_AREAS_DE_TRABALHO.SQL
--
-- Nem todo tempo seu vai para um projeto de cliente. Marketing,
-- comercial, gestão, financeiro — isso é trabalho, custa hora, e hoje
-- some todo junto no balaio "geral".
--
-- Com a área registrada, o relatório de Tempo passa a responder uma
-- pergunta que ele não respondia: quanto do seu mês foi para atender
-- cliente e quanto foi para tocar o negócio.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════

-- Área do trabalho, quando o tempo NÃO é de um projeto de cliente.
-- Fica nulo quando há projeto: ali quem identifica é o próprio projeto.
alter table public.time_entries
  add column if not exists area text;

create index if not exists idx_time_area on public.time_entries(area, started_at desc);


-- ──────────── LISTA DE ÁREAS ────────────
-- Guardada como texto no app_settings para você poder mudar direto na
-- tela de Tempo, sem precisar de mim e sem rodar SQL de novo.
-- Uma por linha.
insert into public.app_settings (key, value)
values ('areas_trabalho', 'Marketing
Comercial / prospecção
Gestão do negócio
Financeiro
Administrativo
Estudo e formação
Suporte a cliente')
on conflict (key) do nothing;
