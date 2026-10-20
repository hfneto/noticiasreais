# Notícias Reais — manual do pipeline

Este repositório é um app de notícias (PWA estático no GitHub Pages) no estilo Ground News: cada história mostra quem cobriu, de que lado do espectro, como governo e oposição enquadram, e um resumo que separa **fato**, **inferência/opinião** e **alegação em disputa**.

O conteúdo é gerado por sessões agendadas do Claude Code (Routines). Este arquivo é o manual que essas sessões seguem.

- `index.html`, `sw.js`, `manifest.webmanifest`, `icons/`: o app. Não mexa sem pedido do usuário.
- `ios/`: app nativo para iPhone (SwiftUI + widget), que lê os mesmos JSONs. Não mexa sem pedido do usuário; se mudar o esquema dos JSONs, os modelos em `ios/Shared/Modelos.swift` precisam acompanhar.
- `data/fontes.json`: lista curada de veículos com viés e propriedade. Pode **acrescentar** veículos; não mude o viés de um veículo existente sem pedido do usuário.
- `data/edicoes/AAAA-MM-DD.json`: edição diária.
- `data/buscas/<slug>.json`: resultado de uma busca por assunto.
- `data/index.json`: gerado por `scripts/validar.py`. Nunca edite à mão.
- `scripts/feeds.json` e `scripts/coletar_feeds.py`: coleta de manchetes por RSS (GitHub Actions). Pode acrescentar feeds de veículos já cadastrados em `fontes.json`.

## Manchetes por RSS (use sempre)

Esta sessão não abre sites e o buscador cobre mal vários veículos. Por isso um GitHub Action lê, de hora em hora, os feeds RSS de cerca de 80 veículos (`scripts/feeds.json`) e publica as manchetes das últimas 36 h no branch `feeds`:

```bash
git fetch -q origin feeds && git show FETCH_HEAD:manchetes.json > /tmp/manchetes.json
python3 -c "import json;d=json.load(open('/tmp/manchetes.json'));print(d['coletado_em'],len(d['itens']),'manchetes')"
```

Cada item tem `fonte` (id em `fontes.json`), `titulo`, `url` e `publicado_em`. Use esse arquivo para: (1) ver quais assuntos aparecem em muitos veículos (pauta); (2) achar a matéria de cada lado sobre uma história, procurando por palavras-chave nos títulos; (3) detectar pontos cegos (história que só aparece nos feeds de um lado). Combine com WebSearch para contexto, checagens e veículos sem feed. Se o arquivo tiver mais de 3 h (`coletado_em`), siga só com WebSearch e avise no resumo final.

## Tarefa 1 — edição diária

1. Data de hoje em Brasília: `TZ=America/Sao_Paulo date +%F`.
2. Leia as manchetes do branch `feeds` (seção acima). Levante as histórias mais importantes das últimas 24h: **8 a 12 histórias**, cerca de 2/3 Brasil e 1/3 mundo. Critério: relevância pública (política, economia, justiça, saúde, ciência, clima, internacional), não volume de cliques. Evite fofoca, celebridade e esporte, salvo fato de grande impacto.
   - Busque em vários veículos de lados diferentes (veja `data/fontes.json`), não só nos grandes portais. Uma história que só um lado está cobrindo é exatamente o que o app quer mostrar (ponto cego).
3. Para cada história, pesquise a cobertura e monte o objeto conforme o **Esquema** abaixo. Meta: **6 a 12 matérias** por história, cobrindo esquerda, centro e direita quando existirem. Se procurou um lado e não achou cobertura, diga isso em `ponto_cego`.
4. Grave em `data/edicoes/<data>.json`, rode `python3 scripts/validar.py data/edicoes/<data>.json` e corrija até passar.
5. Publique (seção **Publicar**).

## Tarefa 2 — fila de buscas

O usuário pede buscas abrindo uma issue com título `busca: <assunto>`.

1. Liste as issues abertas:
   `curl -s "https://api.github.com/repos/hfneto/noticiasreais/issues?state=open&per_page=50"`
   Considere só as de título começando com `busca:` (ignore maiúsculas). Ignore as que já aparecem como `issue` em `data/index.json` → `buscas`.
2. Se não houver nenhuma pendente, encerre sem commit.
3. Para cada pendente (no máximo 3 por execução, as mais antigas primeiro):
   - O assunto é o texto depois de `busca:`. O corpo da issue pode ter detalhes.
   - Pesquise como na edição diária, mas focado no assunto: 1 a 4 histórias (os desdobramentos principais), cobertura recente primeiro, contexto quando ajudar.
   - Grave em `data/buscas/<slug>.json` com `"tipo": "busca"`, `slug`, `consulta`, `issue` (número), `gerado_em` e `historias`. Se o slug já existir, sobrescreva (é uma atualização).
   - Valide com `scripts/validar.py`.
   - Tente comentar e fechar a issue (pode falhar por permissão; nesse caso siga em frente, o índice já marca como feita):
     `curl -s -X POST .../issues/<n>/comments -d '{"body":"Pronto: https://hfneto.github.io/noticiasreais/#/b/<slug>"}'`
     `curl -s -X PATCH .../issues/<n> -d '{"state":"closed"}'`
4. Publique.

## Método editorial (vale para tudo)

**Honestidade acima de completude.** Prefira menos histórias bem apuradas a muitas mal apuradas.

- **Nunca invente URL, título, veículo ou citação.** Toda `url` precisa ter aparecido num resultado de busca, numa página que você abriu nesta sessão ou em `manchetes.json` (branch `feeds`). Se não achar o link de uma matéria, não a inclua.
- `titulo` da matéria é o título original publicado (em outra língua, mantenha o original e traduza em `angulo`).
- `angulo` é uma frase sua, curta, dizendo o enfoque daquela matéria (o que ela destaca, o que omite). Não copie parágrafos: o app linka para a matéria original para leitura na íntegra.

### Fatos
Só entra em `fatos` o que é verificável **e** confirmado por **2+ fontes independentes** (veículos de grupos diferentes) **ou** por documento primário (texto de lei, decisão judicial, dado oficial, nota oficial, vídeo do evento). Em `base`, diga qual: `"4 fontes independentes"`, `"Diário Oficial"`, `"decisão do STF"`. Escreva sem adjetivos.

### Inferências e opiniões
Interpretações, previsões, motivações atribuídas, avaliações, projeções de analistas e declarações de autoridades **sobre o que vai acontecer ou por que algo aconteceu**. Sempre com `quem` diz. Uma declaração oficial é um fato ("o ministro disse X"), mas o conteúdo dela, se não verificado, é inferência.

### Em disputa
Alegações relevantes que circulam (em veículos, redes, falas de políticos) e são falsas, sem evidência, exageradas, sem contexto ou contraditórias. Use os rótulos: `Falso`, `Sem evidência`, `Falta contexto`, `Exagerado`, `Distorcido`, `Contraditório`, `Em apuração` (e `Verdadeiro` só quando uma alegação contestada se confirmou). Em `explicacao`, diga **por que** em uma ou duas frases. Se houver checagem de Lupa, Aos Fatos, Estadão Verifica, Fato ou Fake, Comprova ou UOL Confere, ponha em `checagem`. Não rotule como falso o que é só opinião da qual você discorda; nesse caso é inferência. Se não há nada em disputa, deixe a lista vazia.

### Viés
- Matéria de veículo em `fontes.json`: `"fonte": "<id>"`; o app usa o viés cadastrado do veículo.
- Veículo fora da lista ou com `"vies": "nao_classificado"`: `"fonte": null` (ou o id), `"veiculo": "<nome>"`, e avalie **a própria matéria** em `vies_materia` (escolha de fontes ouvidas, adjetivação, o que destaca e omite). Se o veículo aparecer com frequência, acrescente-o a `fontes.json` com `"base": "avaliado pelo pipeline"`.
- `tipo`: `noticia`, `analise`, `opiniao`, `checagem` ou `fonte_primaria`. Não misture opinião com notícia ao comparar lados.

### Governo × oposição (histórias do Brasil)
- `enquadramento` de cada matéria: `pro_governo`, `neutro` ou `oposicao` (em relação ao governo federal), ou `null` se não se aplica.
- `enquadramentos.governo` e `.oposicao`: como cada campo apresenta a história, numa frase cada, com base no que governo/aliados e oposição disseram. `null` se a história não tem esse recorte.

### Visão de fora e ponto cego
- `visao_de_fora`: para histórias do Brasil, como a imprensa estrangeira está tratando (se tratou). Para histórias do mundo, como o tema chega/afeta o Brasil, ou `null`.
- `ponto_cego`: qual lado está cobrindo pouco e o que esse lado deixa de mostrar. `null` se a cobertura é equilibrada.

## Esquema

```json
{
  "tipo": "edicao",
  "data": "2026-10-18",
  "gerado_em": "2026-10-18T06:40:00-03:00",
  "historias": [
    {
      "id": "slug-curto-da-historia",
      "editoria": "Economia",
      "escopo": "brasil",
      "titulo": "Título neutro, sem adjetivo, escrito por você",
      "lide": "Duas frases neutras: o que aconteceu e por que importa.",
      "contexto": "Opcional. Antecedente necessário para entender.",
      "fatos": [{"texto": "...", "base": "3 fontes independentes"}],
      "inferencias": [{"texto": "...", "quem": "Oposição na Câmara"}],
      "em_disputa": [{"alegacao": "...", "rotulo": "Sem evidência", "explicacao": "...", "onde_circula": "redes sociais", "checagem": [{"nome": "Aos Fatos", "url": "https://..."}]}],
      "enquadramentos": {"governo": "...", "oposicao": "..."},
      "visao_de_fora": "...",
      "ponto_cego": "...",
      "materias": [
        {"fonte": "folha", "titulo": "...", "url": "https://...", "angulo": "...", "tipo": "noticia", "enquadramento": "neutro", "data": "2026-10-18"},
        {"fonte": null, "veiculo": "Portal X", "vies_materia": "direita", "titulo": "...", "url": "https://...", "angulo": "...", "tipo": "opiniao", "enquadramento": "oposicao"}
      ]
    }
  ]
}
```

Ordene `historias` por importância. Ordene `materias` misturando lados (não agrupe tudo de um lado no topo).

## Publicar

```bash
git add data/
git commit -m "Edição 2026-10-18"        # ou "Busca: <assunto>"
git pull --rebase origin main
git push -u origin main
```

Publique direto na `main` (o GitHub Pages serve a `main`). Se o push falhar por rede, tente de novo até 4 vezes com espera crescente (2s, 4s, 8s, 16s). Não abra PR para conteúdo.
