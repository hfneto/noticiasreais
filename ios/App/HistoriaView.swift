import SafariServices
import SwiftUI

struct HistoriaView: View {
    @Environment(AppModel.self) private var modelo
    var ref: ColRef
    var id: String
    @State private var colecao: Colecao?
    @State private var carregou = false

    var body: some View {
        Group {
            if let colecao, let i = colecao.historias.firstIndex(where: { $0.id == id }) {
                LeituraView(ref: ref, historias: colecao.historias, indice: i)
            } else if carregou {
                Vazio(titulo: "História não encontrada", texto: "Ela pode ter saído de uma edição antiga que não está mais no aparelho.")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.nrFundo)
        .task {
            colecao = await modelo.colecao(ref)
            carregou = true
        }
    }
}

private struct LeituraView: View {
    @Environment(AppModel.self) private var modelo
    var ref: ColRef
    var historias: [Historia]
    var indice: Int
    @State private var filtro: FiltroCobertura = .todos
    @State private var link: LinkExterno?

    private var h: Historia { historias[indice] }

    var body: some View {
        let cob = modelo.cobertura(h)
        ScrollViewReader { leitor in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(h.editoria) · \(h.materias?.count ?? 0) matérias".uppercased())
                            .font(.rotulo).tracking(1.2).foregroundStyle(Color.nrMudo)
                        Text(h.titulo).font(.manchete(28, peso: .bold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(h.lide).font(.manchete(18, peso: .regular)).lineSpacing(3)
                    if let ctx = h.contexto {
                        Text(ctx).font(.subheadline).foregroundStyle(Color.nrMudo)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.nrLinha).frame(width: 2) }
                    }
                    Button { withAnimation { leitor.scrollTo("cobertura", anchor: .top) } } label: {
                        Label("Ler a cobertura de cada lado", systemImage: "arrow.down")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.nrCartao, in: Capsule())
                            .overlay(Capsule().stroke(Color.nrLinha))
                    }
                    .buttonStyle(.plain)

                    Bloco(titulo: "Fatos", cor: .nrFato, nota: "confirmados por 2+ fontes ou documento") {
                        ForEach(h.fatos ?? [], id: \.self) { f in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(Color.nrFato)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.texto).font(.manchete(17, peso: .regular))
                                    Text(f.base).font(.caption).foregroundStyle(Color.nrMudo)
                                }
                            }
                        }
                    }

                    if let infs = h.inferencias, !infs.isEmpty {
                        Bloco(titulo: "Inferências e opiniões", cor: .nrInferencia) {
                            ForEach(infs, id: \.self) { x in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(x.texto).font(.manchete(17, peso: .regular))
                                    Text(x.quem).font(.caption).foregroundStyle(Color.nrMudo)
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.nrLinha, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                        }
                    }

                    if let disps = h.emDisputa, !disps.isEmpty {
                        Bloco(titulo: "Em disputa", cor: .nrDisputa) {
                            ForEach(disps, id: \.self) { d in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(d.rotulo.uppercased()).font(.rotulo).tracking(1)
                                        .foregroundStyle(d.rotulo == "Verdadeiro" ? Color.nrFato : Color.nrDisputa)
                                    Text(d.alegacao).font(.manchete(17, peso: .regular))
                                    Text(d.explicacao + (d.ondeCircula.map { " Circula em: \($0)." } ?? ""))
                                        .font(.subheadline).foregroundStyle(Color.nrMudo)
                                    ForEach(d.checagem ?? [], id: \.self) { c in
                                        if let u = URL(string: c.url), u.scheme == "https" {
                                            Button("\(c.nome) ↗") { link = LinkExterno(url: u) }
                                                .font(.subheadline.weight(.semibold))
                                        }
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.nrCartao)
                                .overlay(alignment: .leading) { Rectangle().fill(Color.nrDisputa).frame(width: 3) }
                            }
                        }
                    }

                    if let enq = h.enquadramentos, enq.governo != nil || enq.oposicao != nil {
                        Bloco(titulo: "Como cada lado enquadra") {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 10) { quadros(enq) }
                                VStack(spacing: 10) { quadros(enq) }
                            }
                        }
                    }

                    Bloco(titulo: "Cobertura", nota: "\(cob.n) classificadas") {
                        BarraEspectro(cobertura: cob, altura: 8)
                        Percentuais(cobertura: cob)
                        CoberturaLista(historia: h, posicao: indice, filtro: $filtro) { link = LinkExterno(url: $0) }
                    }
                    .id("cobertura")

                    if let fora = h.visaoDeFora {
                        Bloco(titulo: "A visão de fora", cor: .nrFora) { Text(fora).font(.manchete(17, peso: .regular)) }
                    }
                    if let cego = h.pontoCego {
                        Bloco(titulo: "Ponto cego", cor: cob.pontoCego.map { Color.lado($0) } ?? .nrMudo) {
                            Text(cego).font(.manchete(17, peso: .regular))
                        }
                    }

                    HStack(spacing: 10) {
                        if indice > 0 {
                            NavigationLink(value: Rota.historia(ref, historias[indice - 1].id)) {
                                Text("← Anterior").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        if indice + 1 < historias.count {
                            NavigationLink(value: Rota.historia(ref, historias[indice + 1].id)) {
                                Text("Próxima →").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("\(indice + 1) de \(historias.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: Repositorio.webURL("\(ref.webPath)/\(h.id)"), subject: Text(h.titulo), message: Text(h.titulo)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button { modelo.alternarSalvo(ref, h) } label: {
                    Image(systemName: modelo.estaSalvo(ref, h) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(modelo.estaSalvo(ref, h) ? "Remover dos salvos" : "Salvar")
            }
        }
        .sheet(item: $link) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    @ViewBuilder private func quadros(_ enq: Enquadramentos) -> some View {
        if let g = enq.governo { quadro("Governo", g, false) }
        if let o = enq.oposicao { quadro("Oposição", o, true) }
    }

    private func quadro(_ titulo: String, _ texto: String, _ tracejado: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased()).font(.rotulo).tracking(1).foregroundStyle(Color.nrMudo)
            Text(texto).font(.manchete(16, peso: .regular))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.nrCartao)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.nrLinha, style: StrokeStyle(lineWidth: 1, dash: tracejado ? [4, 3] : [])))
    }
}

struct Bloco<Conteudo: View>: View {
    var titulo: String
    var cor: Color? = nil
    var nota: String? = nil
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let cor { Circle().fill(cor).frame(width: 8, height: 8) }
                Text(titulo.uppercased()).font(.rotulo).tracking(1.4)
                Spacer()
                if let nota { Text(nota).font(.caption2).foregroundStyle(Color.nrMudo) }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.nrTinta).frame(height: 2) }
            conteudo
        }
    }
}

enum FiltroCobertura: String, CaseIterable, Identifiable {
    case todos = "Todos", esquerda = "Esquerda", centro = "Centro", direita = "Direita"
    case governo = "Pró-governo", oposicao = "Oposição", estrangeira = "Estrangeira", opiniao = "Opinião"
    var id: String { rawValue }
}

private struct CoberturaLista: View {
    @Environment(AppModel.self) private var modelo
    var historia: Historia
    var posicao: Int
    @Binding var filtro: FiltroCobertura
    var abrir: (URL) -> Void

    private struct Item: Identifiable {
        var m: Materia
        var vies: String
        var porMateria: Bool
        var lado: Lado?
        var estrangeira: Bool
        var id: String { m.id }
    }

    private var itens: [Item] {
        let todos = (historia.materias ?? []).map { m -> Item in
            let v = Vies.daMateria(m, fontes: modelo.fontes)
            return Item(m: m, vies: v.vies, porMateria: v.porMateria, lado: Lado(vies: v.vies),
                        estrangeira: Vies.estrangeira(m, historia: historia, fontes: modelo.fontes))
        }
        // a ordem dos lados gira a cada história, para nenhum lado aparecer sempre primeiro
        let base: [Lado] = [.esquerda, .centro, .direita]
        let ordem = (0..<3).map { base[($0 + posicao) % 3] }
        let grupos = ordem.map { l in todos.filter { $0.lado == l } }
        var intercalado: [Item] = []
        for k in 0..<(grupos.map(\.count).max() ?? 0) {
            for g in grupos where k < g.count { intercalado.append(g[k]) }
        }
        return intercalado + todos.filter { $0.lado == nil }
    }

    private func passa(_ i: Item, _ f: FiltroCobertura) -> Bool {
        switch f {
        case .todos: return true
        case .esquerda: return i.lado == .esquerda
        case .centro: return i.lado == .centro
        case .direita: return i.lado == .direita
        case .governo: return i.m.enquadramento == "pro_governo"
        case .oposicao: return i.m.enquadramento == "oposicao"
        case .estrangeira: return i.estrangeira
        case .opiniao: return i.m.tipo == "opiniao" || i.m.tipo == "analise"
        }
    }

    var body: some View {
        let lista = itens
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FiltroCobertura.allCases) { f in
                    let n = lista.filter { passa($0, f) }.count
                    Button { filtro = f } label: {
                        Text("\(f.rawValue) \(n)")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(filtro == f ? Color.nrFundo : Color.nrTinta)
                            .background(filtro == f ? Color.nrTinta : Color.nrCartao, in: Capsule())
                            .overlay(Capsule().stroke(filtro == f ? Color.nrTinta : Color.nrLinha))
                    }
                    .buttonStyle(.plain)
                    .disabled(n == 0)
                    .opacity(n == 0 ? 0.4 : 1)
                }
            }
        }
        let visiveis = lista.filter { passa($0, filtro) }
        if visiveis.isEmpty {
            Text("Nenhuma matéria neste recorte.").font(.subheadline).foregroundStyle(Color.nrMudo)
        }
        ForEach(visiveis) { i in
            VStack(alignment: .leading, spacing: 4) {
                cabecalho(i)
                Text(i.m.titulo).font(.manchete(17))
                if let a = i.m.angulo { Text(a).font(.subheadline).foregroundStyle(Color.nrMudo) }
                if let u = URL(string: i.m.url), u.scheme == "https" {
                    Button { abrir(u) } label: {
                        Text("Ler na íntegra em \(u.host()?.replacingOccurrences(of: "www.", with: "") ?? "site") ↗")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.nrAcao)
                }
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.nrLinha).frame(height: 1) }
        }
    }

    private func cabecalho(_ i: Item) -> some View {
        let nome = i.m.fonte.flatMap { modelo.fontes[$0]?.nome } ?? i.m.veiculo ?? "Veículo"
        var partes = "\(nome) · \(Vies.nomes[i.vies] ?? "—")"
        if i.porMateria { partes += " (pela matéria)" }
        if i.estrangeira { partes += " · estrangeira" }
        if let t = i.m.tipo, t != "noticia" { partes += " · " + (["analise": "análise", "opiniao": "opinião", "checagem": "checagem", "fonte_primaria": "fonte primária"][t] ?? t) }
        if i.m.enquadramento == "pro_governo" { partes += " · pró-governo" }
        if i.m.enquadramento == "oposicao" { partes += " · oposição" }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(Color.lado(i.lado)).frame(width: 8, height: 8)
            Text(partes).font(.caption.weight(.semibold)).foregroundStyle(Color.nrMudo)
        }
    }
}

struct LinkExterno: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
