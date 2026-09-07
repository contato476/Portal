# Conectar o Instagram ao sistema

O sistema puxa as métricas do Instagram direto da API da Meta. O trabalho
de configuração é feito **uma vez**, e depois é só clicar em
**🔄 Sincronizar Instagram** na tela de Marketing.

> **Enquanto isso não estiver pronto, a tela funciona normalmente.**
> Use **📋 Importar colando** (cola os números de uma planilha) ou
> **+ Registrar métricas** (digita à mão). Nada fica travado esperando a Meta.

---

## Antes de começar

Você vai precisar de:

- Uma conta do Instagram do tipo **Comercial** (não serve pessoal nem criador)
- Uma **Página do Facebook** vinculada a essa conta
- Acesso ao painel da Vercel para colar duas variáveis

Leva uns 20 minutos na primeira vez.

---

## Passo 1 — Deixar a conta do Instagram como Comercial

No app do Instagram: **Configurações → Tipo de conta e ferramentas →
Mudar para conta profissional → Empresa**.

## Passo 2 — Vincular a uma Página do Facebook

Ainda no Instagram: **Configurações → Central de Contas** (ou
*Contas vinculadas*) → conectar a Página do Facebook.

Se você não tem Página, crie uma em facebook.com/pages/create — pode ser
simples, ela só serve de ponte. A Meta não libera as métricas sem isso.

## Passo 3 — Criar o app na Meta

1. Entre em **developers.facebook.com** com a sua conta do Facebook
2. **Meus apps → Criar app**
3. Tipo do app: **Empresa** (Business)
4. Dentro do app: **Adicionar produto → Instagram Graph API**

> Não precisa passar por Análise do App (App Review) enquanto o app
> estiver em modo **Desenvolvimento** e você for administradora da própria
> conta. Que é exatamente o seu caso.

## Passo 4 — Gerar o token

1. Vá em **Ferramentas → Explorador da Graph API**
2. No canto direito, selecione o seu app
3. Em **Permissões**, adicione as quatro:
   - `instagram_basic`
   - `instagram_manage_insights`
   - `pages_show_list`
   - `pages_read_engagement`
4. Clique em **Gerar token de acesso** e autorize

Guarde esse token — ele é curto (vale ~1 hora) e será trocado no passo 6.

## Passo 5 — Descobrir o IG_USER_ID

Ainda no Explorador da Graph API, faça duas chamadas:

1. Digite `me/accounts` e envie → copie o `id` da sua Página
2. Digite `{id-da-pagina}?fields=instagram_business_account` e envie

O `id` que aparecer dentro de `instagram_business_account` é o seu
**IG_USER_ID**. Anote.

## Passo 6 — Trocar por um token de 60 dias

O token do passo 4 vale só 1 hora. Para transformar num de 60 dias, cole
esta URL no navegador, trocando as três partes em maiúsculas:

```
https://graph.facebook.com/v23.0/oauth/access_token?grant_type=fb_exchange_token&client_id=SEU_APP_ID&client_secret=SEU_APP_SECRET&fb_exchange_token=TOKEN_DO_PASSO_4
```

O **App ID** e o **App Secret** estão em: seu app → **Configurações → Básico**.

A resposta traz um `access_token` novo. **Esse é o que você vai usar.**

## Passo 7 — Colar na Vercel

No painel da Vercel: seu projeto → **Settings → Environment Variables**.
Crie estas cinco:

| Nome | Valor |
|---|---|
| `IG_ACCESS_TOKEN` | o token de 60 dias do passo 6 |
| `IG_USER_ID` | o id do passo 5 |
| `IG_API_VERSION` | `v23.0` |
| `SUPABASE_URL` | `https://jvtjhfganuuefswbnbrk.supabase.co` |
| `SUPABASE_ANON_KEY` | a mesma chave pública que o site já usa (está em `assets/shared.js`) |

Depois clique em **Redeploy** — as variáveis só valem no próximo deploy.

## Passo 8 — Testar

Abra a tela de **Marketing** e clique em **🔄 Sincronizar Instagram**.

---

## Renovar a cada 60 dias

O token expira em 60 dias e a Meta não renova sozinha. A tela de Marketing
avisa quando faltarem 20 dias e destaca em vermelho quando faltarem 10.

Para renovar: repita os passos 4 e 6, e atualize o `IG_ACCESS_TOKEN` na
Vercel. É uma ação a cada dois meses.

> **Por que não automatizar?** Daria — mas para isso o token teria que
> ficar guardado no banco e trafegar até o navegador. Hoje ele existe
> **só no servidor** e nunca sai de lá. Preferi manter assim: dois
> minutos a cada dois meses valem mais que um segredo a mais circulando.

---

## Se der erro

**"Integração não configurada"**
As variáveis não chegaram na função. Confira se você fez o **Redeploy**
depois de criá-las.

**"Não autorizado"**
Sua sessão no sistema expirou. Saia e entre de novo.

**Sincronizou, mas apareceram "ressalvas"**
Normal. A Meta aposenta e renomeia métricas com frequência (`impressions`
virou `views`, `follower_count` está mudando). O sistema busca cada grupo
de métricas separado justamente para que uma que sumiu não derrube as
outras. O que veio foi importado; o que faltou você completa à mão.

**"Object with ID does not exist" ou erro de permissão**
Quase sempre é o passo 2: a conta do Instagram não está vinculada a uma
Página do Facebook, ou está vinculada a uma Página em que você não é
administradora.

---

## O que a sincronização traz — e o que não traz

| No sistema | Vem da Meta |
|---|---|
| Contas alcançadas | `reach` |
| Visualizações | `views` |
| Interações | `total_interactions` |
| Visitas ao perfil | `profile_views` |
| Toques no link da bio | `website_clicks` |
| Seguidores líquidos | `follower_count` |
| Total de seguidores | `followers_count` (foto de hoje, não histórico) |
| **Leads gerados** | **nada — sempre seu** |

**Leads continua manual, de propósito.** A Meta sabe quantas pessoas
clicaram no link; ela não tem como saber quais viraram conversa de
verdade. Esse número só existe na sua cabeça e no CRM — e é justamente
ele que diz se o Instagram está dando retorno.
