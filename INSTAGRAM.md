# Conectar o Instagram ao sistema

São **4 passos**. A Meta lançou um caminho novo (*Instagram API with
Instagram Login*) que dispensa a Página do Facebook e as variáveis de
ambiente — o que tornava isso chato desapareceu.

> **Enquanto não fizer, nada trava.** Use **📋 Importar colando** (cola os
> números de uma planilha) ou **+ Registrar métricas**. A tela funciona igual.

---

## Antes de começar

Só uma coisa: a conta do Instagram precisa ser **profissional** —
Comercial ou Criador, tanto faz.

No app: **Configurações → Tipo de conta e ferramentas → Mudar para conta
profissional**.

**Você NÃO precisa de Página do Facebook.** Era o passo mais irritante do
caminho antigo, e ele não existe mais aqui.

---

## Passo 1 — Criar o app na Meta

> Se você já tentou por **developers.facebook.com/tools** e travou: aquela
> página é só a lista de ferramentas, e nenhuma funciona antes de existir
> um app. Comece por `/apps`, não por `/tools`.

1. Vá em **developers.facebook.com/apps**
2. Botão verde **Criar app**
3. Se perguntar o que o app vai fazer, escolha **Outro** → tipo **Empresa**
4. Dê um nome qualquer (ex.: "Gestão Jenneffer") e confirme

## Passo 2 — Adicionar o produto certo

Dentro do app, menu esquerdo: **Adicionar produto** → procure
**Instagram** → **Configurar**.

Escolha a opção **API com login do Instagram** (*Instagram API with
Instagram Login*). É essa que dispensa a Página do Facebook.

Em seguida, conecte a sua conta do Instagram quando ele pedir.

## Passo 3 — Gerar o token

Ainda na tela do produto Instagram, procure **Gerar token de acesso**
(fica junto da conta que você conectou).

Ao gerar, confirme que estão marcadas as permissões:

- `instagram_business_basic`
- `instagram_business_manage_insights`

Essas duas bastam para as métricas. As de mensagens e comentários **não
são necessárias** — não marque o que você não vai usar.

Copie o token que aparecer. Ele é longo e começa com `IGQ...`.

## Passo 4 — Colar no sistema

Abra a tela **Marketing** → **Conectar agora** → cole o token → **Conectar
e sincronizar**.

Pronto. Ele já traz os últimos 7 dias.

---

## Sobre a renovação: você não precisa fazer nada

O token vale 60 dias — mas **o sistema renova sozinho**. Toda vez que você
sincroniza, ele confere quanto falta e, se estiver perto de vencer, pede
um token novo à Meta e guarda no lugar do antigo.

Na prática: enquanto você abrir o Marketing pelo menos uma vez a cada dois
meses, isso funciona para sempre sem você tocar.

A tela avisa se a renovação começar a falhar, com dias de folga. Só nesse
caso você gera outro token (passo 3) e cola de novo.

> **Por que o token fica no banco e não numa variável da Vercel?**
> Porque a Vercel não deixa uma função reescrever a própria variável — e
> sem reescrever, não dá para renovar. Guardado no Supabase, numa tabela
> que só você lê, a renovação acontece sozinha. O token nunca é devolvido
> ao navegador: quem lê e usa é a função no servidor.

---

## O que vem da Meta e o que continua seu

| No sistema | De onde vem |
|---|---|
| Contas alcançadas | `reach` — série diária de verdade |
| Visualizações | `views` |
| Interações | `total_interactions` |
| Toques no link da bio | `profile_links_taps` |
| Seguidores líquidos | `follows_and_unfollows` (seguiu − deixou de seguir) |
| Total de seguidores | foto do dia de hoje, não histórico |
| **Visitas ao perfil** | **não vem mais** — a Meta tirou da API nova |
| **Posts publicados** | **seu** |
| **Leads gerados** | **seu** |

**Leads continua manual de propósito.** A Meta sabe quem clicou; ela não
sabe quem virou conversa. Esse número só existe na sua cabeça e no CRM — e
é justamente ele que diz se o Instagram está dando retorno.

**Visitas ao perfil** você ainda vê no app do Instagram; se quiser no
sistema, anote pelo **+ Registrar métricas**.

---

## Se der erro

**"Instagram ainda não conectado"**
O token não foi salvo, ou foi desconectado. Clique em Conectar e cole de novo.

**"O acesso ao Instagram não está valendo"**
O token expirou ou foi revogado. Gere outro no passo 3.

**Sincronizou, mas veio com "ressalvas"**
Normal. A Meta aposenta e renomeia métricas com frequência (`impressions`
virou `views`, `profile_views` sumiu). O sistema busca cada coisa
separada justamente para que uma que mudou não derrube o resto. O que veio
foi importado; o que faltou você completa à mão.

**Erro de permissão nos insights**
Faltou marcar `instagram_business_manage_insights` no passo 3. Gere o
token de novo com ela marcada.

---

## O que este sistema NÃO faz (e onde fazer)

Responder DM automático, "comenta a palavra X que eu te mando o link",
mensagem de ausência — nada disso passa por aqui.

Duas razões: exige uma análise do app pela Meta (com vídeo, verificação de
negócio e caminho de descadastro), e o Instagram já entrega isso de graça
no **Meta Business Suite** (desktop): respostas automáticas, palavras-chave
e comentário→DM. Se precisar de mais, ferramentas como ManyChat resolvem
por uns US$ 10–15/mês.
