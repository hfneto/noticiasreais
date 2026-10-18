import SwiftUI

enum Secao: String, CaseIterable, Identifiable {
    case hoje = "Hoje", brasil = "Brasil", mundo = "Mundo", cegos = "Pontos cegos"
    var id: String { rawValue }
}

struct FeedView: View {
    @Environment(AppModel.self) private var modelo
    @State private var secao: Secao = .hoje

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cabecalho
                seletor
                conteudo
            }
        }
        .background(Color.nrFundo)
        .refreshable { await modelo.atualizar() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(modelo.edicaoAtual.map { Datas.extenso($0.data) }?.uppercased() ?? "NOTÍCIAS REAIS")
                .font(.rotulo).tracking(1.2).foregroundStyle(Color.nrMudo)
            Text("Notícias Reais").font(.manchete(34, peso: .bold))
            if let e = modelo.edicaoAtual {
                Text("\(e.historias) histórias · gerada às \(Datas.hora(Datas.iso(e.geradoEm)))")
                    .font(.subheadline).foregroundStyle(Color.nrMudo)
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
    }

    private var seletor: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(Secao.allCases) { s in
                    Button { secao = s } label: {
                        Text(s.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(secao == s ? Color.nrTinta : Color.nrMudo)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(secao == s ? Color.nrAcao : .clear).frame(height: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var conteudo: some View {
        if let e = modelo.edicaoAtual, let col = modelo.colecoes[.edicao(e.data)] {
            let lista = filtrar(col.historias)
            LazyVStack(spacing: 12) {
                if secao == .cegos {
                    Text("Histórias que um lado do espectro quase não está cobrindo")
                        .font(.rotulo).tracking(1).foregroundStyle(Color.nrMudo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(lista) { h in
                    NavigationLink(value: Rota.historia(.edicao(e.data), h.id)) {
                        CartaoHistoria(historia: h, cobertura: modelo.cobertura(h))
                    }
                    .buttonStyle(.plain)
                }
                if lista.isEmpty {
                    Vazio(titulo: "Nada aqui hoje", texto: secao == .cegos ? "Nenhuma história desta edição tem cobertura muito desequilibrada." : "Nada nesta seção hoje.")
                }
                if secao == .hoje {
                    VStack(spacing: 4) {
                        Text("Você está em dia").font(.manchete(18))
                        Text("A próxima edição sai amanhã cedo.").font(.footnote).foregroundStyle(Color.nrMudo)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .background(Color.nrCartao, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.nrLinha))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
        } else if let erro = modelo.erro {
            Vazio(titulo: "Sem conexão", texto: erro)
        } else if modelo.indice != nil && modelo.edicaoAtual == nil {
            Vazio(titulo: "A primeira edição está a caminho", texto: "Ela é gerada todo dia de manhã.")
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        }
    }

    private func filtrar(_ hs: [Historia]) -> [Historia] {
        switch secao {
        case .hoje: return hs
        case .brasil: return hs.filter { $0.escopo == "brasil" }
        case .mundo: return hs.filter { $0.escopo == "mundo" }
        case .cegos: return hs.filter { modelo.cobertura($0).pontoCego != nil }
        }
    }
}

struct CartaoHistoria: View {
    var historia: Historia
    var cobertura: Cobertura

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(historia.editoria) · \(historia.escopo == "mundo" ? "Mundo" : "Brasil")".uppercased())
                Spacer()
                Text("\(historia.materias?.count ?? 0) MATÉRIAS")
            }
            .font(.rotulo).tracking(1).foregroundStyle(Color.nrMudo).monospacedDigit()

            Text(historia.titulo).font(.manchete(20)).foregroundStyle(Color.nrTinta)
                .fixedSize(horizontal: false, vertical: true)
            Text(historia.lide).font(.subheadline).foregroundStyle(Color.nrMudo).lineLimit(2)
            BarraEspectro(cobertura: cobertura)
            Percentuais(cobertura: cobertura)
            Etiquetas(historia: historia, cobertura: cobertura)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nrCartao, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.nrLinha))
        .contentShape(Rectangle())
    }
}

struct Etiquetas: View {
    var historia: Historia
    var cobertura: Cobertura

    var body: some View {
        let disputas = historia.emDisputa?.count ?? 0
        if cobertura.pontoCego != nil || cobertura.gov + cobertura.op > 0 || disputas > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let l = cobertura.pontoCego {
                        Etiqueta(texto: "Pouco coberto pela \(l.nome.lowercased())", cor: .lado(l), contorno: true)
                    }
                    if cobertura.gov + cobertura.op > 0 {
                        Etiqueta(texto: "Pró-governo \(cobertura.gov) · Oposição \(cobertura.op)", cor: .nrTinta)
                    }
                    if disputas > 0 {
                        Etiqueta(texto: disputas == 1 ? "1 alegação em disputa" : "\(disputas) alegações em disputa", cor: .nrDisputa)
                    }
                }
            }
        }
    }
}

struct Etiqueta: View {
    var texto: String
    var cor: Color
    var contorno = false

    var body: some View {
        Text(texto)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(cor)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(contorno ? Color.clear : Color.nrSuave, in: Capsule())
            .overlay(Capsule().stroke(contorno ? cor : .clear))
    }
}

struct Vazio: View {
    var titulo: String
    var texto: String

    var body: some View {
        VStack(spacing: 6) {
            Text(titulo).font(.manchete(20))
            Text(texto).font(.subheadline).foregroundStyle(Color.nrMudo).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}
