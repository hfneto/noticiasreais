import Foundation
import Observation
import WidgetKit

struct Salvo: Codable, Identifiable, Hashable {
    var ref: ColRef
    var historia: Historia
    var origem: String
    var salvoEm: Date
    var id: String { ref.webPath + "/" + historia.id }
}

@MainActor
@Observable
final class AppModel {
    var indice: Indice?
    var fontes: [String: Fonte] = [:]
    var tiposPropriedade: [String: String] = [:]
    var colecoes: [ColRef: Colecao] = [:]
    var salvos: [Salvo] = []
    var carregando = false
    var erro: String?
    var offline = false

    private var arquivoSalvos: URL { Repositorio.pasta.appendingPathComponent("salvos.json") }

    init() {
        if let dados = try? Data(contentsOf: arquivoSalvos),
           let lista = try? JSONDecoder().decode([Salvo].self, from: dados) {
            salvos = lista
        }
    }

    var edicaoAtual: EdicaoMeta? { indice?.edicoes.first }

    func cobertura(_ h: Historia) -> Cobertura { Cobertura(h, fontes: fontes) }

    /// Atualiza índice, fontes e a edição mais recente. Sem rede, usa o que estiver em disco.
    func atualizar() async {
        guard !carregando else { return }
        carregando = true
        defer { carregando = false }
        do {
            async let i = Repositorio.indice()
            async let f = Repositorio.carregar("data/fontes.json", como: FontesDoc.self)
            let (novoIndice, doc) = try await (i, f)
            indice = novoIndice
            fontes = Dictionary(uniqueKeysWithValues: doc.fontes.map { ($0.id, $0) })
            tiposPropriedade = doc.tiposPropriedade
            if let atual = novoIndice.edicoes.first {
                colecoes[.edicao(atual.data)] = try await Repositorio.colecao(atual.arquivo)
            }
            erro = nil
            WidgetCenter.shared.reloadAllTimelines()
            await Notificacoes.atualizarManchete(indice: novoIndice)
        } catch {
            erro = indice == nil ? "Não consegui carregar as notícias. Verifique a conexão e puxe para atualizar." : nil
        }
    }

    func colecao(_ ref: ColRef) async -> Colecao? {
        if let c = colecoes[ref] { return c }
        guard let indice else { return nil }
        let arquivo: String?
        switch ref {
        case .edicao(let d): arquivo = indice.edicoes.first { $0.data == d }?.arquivo
        case .busca(let s): arquivo = indice.buscas.first { $0.slug == s }?.arquivo
        }
        guard let arquivo, let c = try? await Repositorio.colecao(arquivo) else { return nil }
        colecoes[ref] = c
        return c
    }

    func rotulo(_ ref: ColRef) -> String {
        switch ref {
        case .edicao(let d): return d == edicaoAtual?.data ? "Edição de hoje" : Datas.extenso(d)
        case .busca(let s): return "Busca: " + (indice?.buscas.first { $0.slug == s }?.consulta ?? s)
        }
    }

    // MARK: salvos

    func estaSalvo(_ ref: ColRef, _ h: Historia) -> Bool {
        salvos.contains { $0.ref == ref && $0.historia.id == h.id }
    }

    func alternarSalvo(_ ref: ColRef, _ h: Historia) {
        if let i = salvos.firstIndex(where: { $0.ref == ref && $0.historia.id == h.id }) {
            salvos.remove(at: i)
        } else {
            salvos.insert(Salvo(ref: ref, historia: h, origem: rotulo(ref), salvoEm: Date()), at: 0)
        }
        if let dados = try? JSONEncoder().encode(salvos) {
            try? dados.write(to: arquivoSalvos, options: .atomic)
        }
    }

    func remover(salvos offsets: IndexSet) {
        salvos.remove(atOffsets: offsets)
        if let dados = try? JSONEncoder().encode(salvos) {
            try? dados.write(to: arquivoSalvos, options: .atomic)
        }
    }

    /// Histórias das últimas edições que contêm o termo (busca local, funciona offline com o que já foi baixado).
    func buscarLocal(_ termo: String) async -> [(ColRef, Historia)] {
        let t = termo.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
        guard t.count >= 3, let indice else { return [] }
        var achados: [(ColRef, Historia)] = []
        for meta in indice.edicoes.prefix(14) {
            let ref = ColRef.edicao(meta.data)
            guard let c = await colecao(ref) else { continue }
            for h in c.historias {
                let alvo = (h.titulo + " " + h.lide + " " + h.editoria)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
                if alvo.contains(t) { achados.append((ref, h)) }
            }
        }
        return achados
    }
}
