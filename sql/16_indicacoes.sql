-- ════════════════════════════════════════════════════════════════════
-- 16_INDICACOES.SQL
-- Programa de indicação — cashback para quem indica.
--
-- POR QUÊ ISTO EXISTE: cliente satisfeito indica, e hoje isso some.
-- O CRM registra "origem: indicação", mas não QUEM indicou, quanto essa
-- pessoa tem a receber por isso, nem se já foi paga. Sem esse registro,
-- ou você paga de memória ou não paga — e as duas coisas custam caro.
--
-- COMO FUNCIONA
--   1. Cada cliente tem uma regra: quanto ele ganha ao indicar. Pode ser
--      um valor fixo (R$ 200 por indicação) ou uma porcentagem do
--      negócio fechado (5% do contrato). Quem não tem regra própria usa
--      o padrão do programa, guardado no app_settings.
--   2. Você registra a indicação: fulano indicou beltrano.
--   3. Quando o indicado fecha, o cashback é apurado e entra na fila de
--      pagamento. Ao pagar, vira uma despesa no Financeiro.
--
-- A regra fica CONGELADA na indicação (reward_type/reward_value): se
-- você mudar o programa depois, o que já foi prometido não muda.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. A REGRA DE CADA CLIENTE ────────────
-- Nulo = usa o padrão do programa.
alter table public.crm_contacts
  add column if not exists referral_reward_type text
      check (referral_reward_type in ('valor','percent')),
  add column if not exists referral_reward_value numeric(12,2);


-- ──────────── 2. AS INDICAÇÕES ────────────
-- referred_contact_id fica nulo enquanto o indicado for só um nome: nem
-- toda indicação vira contato no CRM, e forçar isso encheria o CRM de
-- gente que nunca respondeu.
create table if not exists public.referrals (
  id                  uuid primary key default gen_random_uuid(),
  referrer_contact_id uuid not null references public.crm_contacts(id) on delete cascade,
  referred_contact_id uuid references public.crm_contacts(id) on delete set null,
  referred_name       text not null,
  referred_company    text,
  referred_email      text,
  referred_phone      text,
  deal_id             uuid references public.crm_deals(id) on delete set null,

  -- Onde a indicação está: chegou, está conversando, fechou ou não deu.
  status              text not null default 'indicado'
                      check (status in ('indicado','em_conversa','fechou','nao_fechou')),

  -- A regra valendo no dia da indicação (congelada de propósito).
  reward_type         text not null default 'valor'
                      check (reward_type in ('valor','percent')),
  reward_value        numeric(12,2) not null default 0,

  -- O cashback apurado, em reais. Só existe depois que fecha.
  reward_amount       numeric(12,2),
  reward_status       text not null default 'a_liberar'
                      check (reward_status in ('a_liberar','a_pagar','pago','cancelado')),
  paid_at             date,
  -- A despesa gerada no Financeiro quando você paga.
  transaction_id      uuid references public.fin_transactions(id) on delete set null,

  notes               text,
  referred_at         date not null default current_date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- Ninguém indica a si mesmo.
  constraint referrals_nao_indica_a_si_mesmo
    check (referred_contact_id is null or referred_contact_id <> referrer_contact_id)
);
create index if not exists idx_referrals_referrer on public.referrals(referrer_contact_id, referred_at desc);
create index if not exists idx_referrals_status   on public.referrals(status);
create index if not exists idx_referrals_reward   on public.referrals(reward_status);

drop trigger if exists trg_referrals_updated on public.referrals;
create trigger trg_referrals_updated
  before update on public.referrals
  for each row execute function public.set_updated_at();


-- ──────────── 3. PERMISSÕES ────────────
-- Tela de gestão: só você. O cliente não vê o programa por dentro.
alter table public.referrals enable row level security;

drop policy if exists "admin_all" on public.referrals;
create policy "admin_all" on public.referrals
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 4. O PADRÃO DO PROGRAMA ────────────
-- Vale para quem não tem regra própria. Editável na tela de Indicações.
insert into public.app_settings (key, value)
values ('indicacao_padrao_tipo', 'valor')
on conflict (key) do nothing;

insert into public.app_settings (key, value)
values ('indicacao_padrao_valor', '0')
on conflict (key) do nothing;


-- ──────────── 5. CATEGORIA NO FINANCEIRO ────────────
-- O cashback pago é despesa, e merece linha própria no relatório: é o
-- custo de aquisição de cliente que veio por indicação.
insert into public.fin_categories (name, kind, color)
values ('Indicações', 'despesa', '#8B5CF6')
on conflict (name, kind) do nothing;
