import SwiftUI
import UserNotifications

/// Lista de histórias de uma edição antiga ou de uma busca.
struct ColecaoView: View {
    @Environment(AppModel.self) private var modelo
    var ref: ColRef
    @State private var colecao: Colecao?
    @State private var carregou = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let colecao {
                    if let r = colecao.resumo { Text(r).font(.subheadline).foregroundStyle(Color.nrMudo) }
                    ForEach(colecao.historias) { h in
                        NavigationLink(value: Rota.historia(ref, h.id)) {
                            CartaoHistoria(historia: h, cobertura: modelo.cobertura(h))
                        }
                        .buttonStyle(.plain)
                    }
                } else if carregou {
                    Vazio(titulo: "Não encontrei", texto: "Sem conexão e sem cópia no aparelho.")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(16)
        }
        .background(Color.nrFundo)
        .navigationTitle(modelo.rotulo(ref))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            colecao = await modelo.colecao(ref)
            carregou = true
        }
    }
}

struct BuscasView: View {
    @Environment(AppModel.self) private var modelo
    @State private var termo = ""
    @State private var locais: [(ColRef, Historia)] = []
    @State private var fila: [IssueBusca]?
    @State private var enviando = false
    @State private var aviso: String?
    private var temToken: Bool { Chaveiro.ler() != nil }

    var body: some View {
        List {
            Section {
                TextField("Ex.: reforma tributária", text: $termo)
                    .submitLabel(.search)
                    .onSubmit { Task { await pedir() } }
                Button {
                    Task { await pedir() }
                } label: {
                    HStack {
                        Text(temToken ? "Pedir pesquisa completa" : "Pedir pesquisa (precisa do token)")
                        if enviando { Spacer(); ProgressView() }
                    }
                }
                .disabled(termo.trimmingCharacters(in: .whitespaces).count < 3 || enviando || !temToken)
            } header: {
                Text("Pesquisar um assunto")
            } footer: {
                Text(temToken
                     ? "A pesquisa com todos os lados fica pronta em até 1 hora (entre 7h e 23h)."
                     : "Só quem cadastrou o token do GitHub em Mais → Ajustes pode pedir pesquisas novas. A busca abaixo procura no que já saiu.")
            }

            if !locais.isEmpty {
                Section("Já no app") {
                    ForEach(locais.indices, id: \.self) { k in
                        NavigationLink(value: Rota.historia(locais[k].0, locais[k].1.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(locais[k].1.titulo).font(.manchete(16))
                                Text(modelo.rotulo(locais[k].0)).font(.caption).foregroundStyle(Color.nrMudo)
                            }
                        }
                    }
                }
            }

            Section("Na fila") {
                if let fila {
                    if fila.isEmpty { Text("Nada na fila.").foregroundStyle(Color.nrMudo) }
                    ForEach(fila) { i in
                        HStack {
                            Text(i.assunto).font(.manchete(16))
                            Spacer()
                            Text(Datas.curta(Datas.iso(i.createdAt))).font(.caption).foregroundStyle(Color.nrMudo)
                        }
                    }
                } else {
                    Text("Não consegui consultar a fila agora.").foregroundStyle(Color.nrMudo)
                }
            }

            Section("Buscas prontas") {
                let buscas = modelo.indice?.buscas ?? []
                if buscas.isEmpty { Text("Nenhuma ainda.").foregroundStyle(Color.nrMudo) }
                ForEach(buscas) { b in
                    NavigationLink(value: Rota.busca(b.slug)) {
                        HStack {
                            Text(b.consulta).font(.manchete(16))
                            Spacer()
                            Text("\(b.historias) hist. · \(Datas.curta(Datas.iso(b.geradoEm)))")
                                .font(.caption).foregroundStyle(Color.nrMudo)
                        }
                    }
                }
            }
        }
        .navigationTitle("Buscas")
        .task(id: termo) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            locais = await modelo.buscarLocal(termo)
        }
        .task { await atualizarFila() }
        .refreshable {
            await modelo.atualizar()
            await atualizarFila()
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func atualizarFila() async {
        fila = await GitHub.fila(feitas: Set((modelo.indice?.buscas ?? []).compactMap(\.issue)))
    }

    private func pedir() async {
        let t = termo.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, temToken else { return }
        enviando = true
        defer { enviando = false }
        do {
            try await GitHub.pedirBusca(t)
            aviso = "Pedido enviado. A pesquisa aparece em Buscas prontas em até 1 hora."
            termo = ""
            await atualizarFila()
        } catch {
            aviso = error.localizedDescription
        }
    }
}

struct SalvosView: View {
    @Environment(AppModel.self) private var modelo

    var body: some View {
        Group {
            if modelo.salvos.isEmpty {
                Vazio(titulo: "Nada salvo ainda", texto: "Toque no marcador no topo de uma história para guardá-la aqui. Ela fica disponível sem internet.")
            } else {
                List {
                    ForEach(modelo.salvos) { s in
                        NavigationLink(value: Rota.historia(s.ref, s.historia.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.historia.titulo).font(.manchete(17))
                                Text(s.origem).font(.caption).foregroundStyle(Color.nrMudo)
                            }
                        }
                    }
                    .onDelete { modelo.remover(salvos: $0) }
                }
            }
        }
        .navigationTitle("Salvos")
    }
}

struct AjustesView: View {
    @Environment(AppModel.self) private var modelo
    @State private var notifAtivas = Notificacoes.ativas
    @State private var hora = AjustesView.dataDaHora(Notificacoes.minutos)
    @State private var token = ""
    @State private var temToken = Chaveiro.ler() != nil
    @AppStorage(Leitura.chaveSafari) private var noSafari = true

    var body: some View {
        Form {
            Section {
                Toggle("Abrir matérias no Safari", isOn: $noSafari)
            } header: {
                Text("Leitura")
            } footer: {
                Text("No Safari valem as suas assinaturas (Estadão, Folha etc.) já logadas. Desligado, as matérias abrem dentro do app, onde é preciso fazer login de novo em cada site.")
            }

            Section {
                Toggle("Avisar quando a edição sair", isOn: $notifAtivas)
                if notifAtivas {
                    DatePicker("Horário", selection: $hora, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Notificação")
            } footer: {
                Text("A edição é gerada por volta das 6h30. Quando o app consegue atualizar antes do aviso, ele traz a manchete.")
            }

            Section {
                if temToken {
                    Label("Token cadastrado", systemImage: "checkmark.seal")
                    Button("Remover token", role: .destructive) {
                        Chaveiro.apagar()
                        temToken = false
                    }
                } else {
                    SecureField("github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Salvar token") {
                        Chaveiro.salvar(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""
                        temToken = true
                    }
                    .disabled(token.count < 20)
                }
            } header: {
                Text("Pedir buscas")
            } footer: {
                Text("Token fine-grained do GitHub com acesso só ao repositório noticiasreais e permissão Issues: leitura e escrita. Fica guardado no Keychain deste aparelho. Sem ele, o app funciona normalmente, mas não pede pesquisas novas.")
            }

            Section("Sobre") {
                NavigationLink("Edições anteriores") { ArquivoView() }
                NavigationLink("Fontes e vieses", value: Rota.fontes)
                NavigationLink("Como funciona", value: Rota.metodo)
                Link("Abrir a versão web", destination: Repositorio.base)
            }
        }
        .navigationTitle("Mais")
        .onChange(of: notifAtivas) { _, ativo in
            Task {
                if ativo {
                    let permitido = await Notificacoes.pedirPermissao()
                    if !permitido {
                        notifAtivas = false
                        return
                    }
                }
                Notificacoes.ativas = ativo
                await reagendar()
            }
        }
        .onChange(of: hora) { _, nova in
            let c = Calendar.current.dateComponents([.hour, .minute], from: nova)
            Notificacoes.minutos = (c.hour ?? 6) * 60 + (c.minute ?? 45)
            Task { await reagendar() }
        }
    }

    private func reagendar() async {
        if let i = modelo.indice { await Notificacoes.atualizarManchete(indice: i) } else { await Notificacoes.reagendar() }
    }

    static func dataDaHora(_ minutos: Int) -> Date {
        Calendar.current.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: Date()) ?? Date()
    }
}

struct ArquivoView: View {
    @Environment(AppModel.self) private var modelo

    var body: some View {
        List(modelo.indice?.edicoes ?? []) { e in
            NavigationLink(value: Rota.edicao(e.data)) {
                HStack {
                    Text(Datas.extenso(e.data)).font(.manchete(16))
                    Spacer()
                    Text("\(e.historias) histórias").font(.caption).foregroundStyle(Color.nrMudo)
                }
            }
        }
        .navigationTitle("Edições anteriores")
    }
}

struct FontesView: View {
    @Environment(AppModel.self) private var modelo

    private func secao(_ titulo: String, _ lista: [Fonte]) -> some View {
        Section(titulo) {
            ForEach(lista.sorted {
                (Vies.ordem.firstIndex(of: $0.vies) ?? 9, $0.nome) < (Vies.ordem.firstIndex(of: $1.vies) ?? 9, $1.nome)
            }) { f in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.lado(Lado(vies: f.vies))).frame(width: 8, height: 8)
                        Text(f.nome).font(.body.weight(.semibold))
                        Spacer()
                        Text(Vies.nomes[f.vies] ?? f.vies).font(.caption).foregroundStyle(Color.nrMudo)
                    }
                    Text("\(f.dono) · \(modelo.tiposPropriedade[f.propriedade] ?? f.propriedade)")
                        .font(.caption).foregroundStyle(Color.nrMudo)
                    if let n = f.notas { Text(n).font(.caption2).foregroundStyle(Color.nrMudo) }
                }
            }
        }
    }

    var body: some View {
        let todas = Array(modelo.fontes.values)
        List {
            Section {
                Text("O viés é do veículo (linha editorial predominante), não de cada matéria. Veículos fora da lista são avaliados pela própria matéria e aparecem marcados \"(pela matéria)\".")
                    .font(.footnote).foregroundStyle(Color.nrMudo)
                Link("Editar a lista no GitHub", destination: URL(string: "https://github.com/\(Repositorio.repo)/edit/main/data/fontes.json")!)
            }
            secao("Brasil", todas.filter { $0.pais == "BR" })
            secao("Internacional", todas.filter { $0.pais != "BR" })
        }
        .navigationTitle("Fontes e vieses")
    }
}

struct MetodoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                item("Fatos", "Só o que foi confirmado por duas ou mais fontes independentes (de grupos diferentes) ou por documento primário: lei, decisão judicial, dado oficial, vídeo do evento. Cada fato diz sua base.")
                item("Inferências e opiniões", "Interpretações, previsões, motivações atribuídas e projeções de analistas, sempre com quem diz.")
                item("Em disputa", "Alegações que circulam e não se sustentam, com rótulos no padrão das agências de checagem brasileiras: Falso, Sem evidência, Falta contexto, Exagerado, Distorcido, Contraditório, Em apuração. Opinião da qual se discorda não entra aqui.")
                item("Cobertura e pontos cegos", "A barra mostra a proporção das matérias encontradas por lado. Uma história vira ponto cego quando um lado tem 20% ou menos da cobertura e o outro 40% ou mais. A ordem dos lados na lista muda a cada história.")
                item("Governo × oposição", "Para histórias do Brasil, cada matéria é marcada como pró-governo, neutra ou de oposição (em relação ao governo federal).")
                item("Limites", "A classificação é feita por IA e pode errar. Leia as matérias originais, que estão sempre linkadas.")
            }
            .padding(18)
        }
        .background(Color.nrFundo)
        .navigationTitle("Como funciona")
    }

    private func item(_ t: String, _ x: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.manchete(19))
            Text(x).font(.body).foregroundStyle(Color.nrTinta)
        }
    }
}
