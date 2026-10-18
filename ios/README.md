# Notícias Reais para iOS

App nativo em SwiftUI (iOS 17+) com widget. Lê o mesmo conteúdo do site (`https://hfneto.github.io/noticiasreais/`), gerado pelas Routines.

- **Hoje:** feed com barra de espectro, pontos cegos e governo × oposição. A matéria vem em blocos: Fatos, Inferências, Em disputa, Enquadramentos, Cobertura (filtrável, abre a matéria original no Safari do app), Visão de fora e Ponto cego.
- **Buscas:** procura no que já saiu (funciona offline). Com o token do GitHub cadastrado, também pede pesquisas novas, que ficam prontas em até 1 hora.
- **Salvos:** histórias marcadas ficam guardadas no aparelho.
- **Widget:** pequeno e médio, com a manchete do dia e a cobertura por lado. Tocar abre a história.
- **Notificação:** aviso diário no horário escolhido. Se o app atualizou em segundo plano antes disso, o aviso traz a manchete.

## 1. Gerar o projeto (uma vez)

```bash
brew install xcodegen
cd ios
xcodegen            # cria NoticiasReais.xcodeproj
open NoticiasReais.xcodeproj
```

Rode `xcodegen` de novo sempre que puxar mudanças que adicionem ou removam arquivos.

## 2. Assinatura

No Xcode, em cada um dos dois targets (**NoticiasReais** e **NoticiasWidget**), abra **Signing & Capabilities**:

1. Marque *Automatically manage signing* e escolha seu **Team**. Para não repetir isso, preencha `DEVELOPMENT_TEAM` em `project.yml` com o seu Team ID (developer.apple.com → Membership).
2. Confira que **App Groups** mostra `group.com.hfneto.noticiasreais` marcado. Se aparecer em vermelho, clique em ↻ e o Xcode registra o grupo.

Se o Bundle ID `com.hfneto.noticiasreais` já estiver em uso, troque o prefixo em `project.yml`: `bundleIdPrefix`, os dois `PRODUCT_BUNDLE_IDENTIFIER` e o App Group. Ajuste também `Repositorio.grupo` em `Shared/Repositorio.swift`.

## 3. Testar no seu iPhone

Conecte o iPhone (ou use a mesma rede Wi-Fi), escolha-o como destino e aperte ▶. Na primeira vez, o iPhone pede para confiar no desenvolvedor: Ajustes → Geral → VPN e Gerenciamento de Dispositivos. Também é preciso ligar o **Modo Desenvolvedor**: Ajustes → Privacidade e Segurança.

## 4. TestFlight (você e pessoas próximas)

1. Em [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → Novo app. Use iOS, o nome (precisa ser único na App Store; se "Notícias Reais" estiver tomado, use algo como "Notícias Reais — Todos os Lados"), idioma Português (Brasil) e o Bundle ID `com.hfneto.noticiasreais`.
2. No Xcode, escolha o destino **Any iOS Device (arm64)**, depois **Product → Archive**, e no Organizer **Distribute App → TestFlight & App Store → Upload**.
3. Em uns 15 minutos o build aparece em App Store Connect → TestFlight.
   - **Teste interno** (você e quem estiver na sua equipe da conta Apple, até 100 pessoas): entra na hora.
   - **Teste externo** (família e amigos por e-mail ou link público, até 10.000 pessoas): o primeiro build passa por uma revisão rápida da Apple, normalmente em até 1 dia.
4. Cada pessoa instala o app **TestFlight** e aceita o convite. Builds do TestFlight valem 90 dias; para renovar, envie um novo, aumentando `CURRENT_PROJECT_VERSION` em `project.yml`.

## 5. Token para pedir buscas (só você)

1. Em github.com → Settings → Developer settings → **Fine-grained tokens** → Generate new token.
2. **Repository access:** Only select repositories → `hfneto/noticiasreais`.
3. **Permissions:** Issues → *Read and write*. Não marque mais nada.
4. No app: Mais → Pedir buscas → cole o token. Ele fica no Keychain do aparelho.

Quem não tem o token usa o app normalmente, só não pede pesquisas novas. Isso mantém as pesquisas sob demanda no seu plano Max, que é de uso pessoal.

## Arquivos

| Pasta | O quê |
|---|---|
| `Shared/` | Modelos dos JSONs, cálculo de cobertura e ponto cego (mesma regra do site), rede com cache no App Group, cores e barra de espectro. Compilado no app e no widget. |
| `App/` | Telas, notificações, atualização em segundo plano, GitHub/Keychain. |
| `Widget/` | Widget da manchete. |
