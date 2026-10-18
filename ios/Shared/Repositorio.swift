import Foundation

/// Lê os JSONs publicados no GitHub Pages, com cópia em disco no App Group (o widget lê a mesma cópia).
enum Repositorio {
    static let base = URL(string: "https://hfneto.github.io/noticiasreais/")!
    static let repo = "hfneto/noticiasreais"
    static let grupo = "group.com.hfneto.noticiasreais"

    static var pasta: URL {
        let raiz = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let p = raiz.appendingPathComponent("dados", isDirectory: true)
        try? FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        return p
    }

    private static func arquivoLocal(_ caminho: String) -> URL {
        pasta.appendingPathComponent(caminho.replacingOccurrences(of: "/", with: "__"))
    }

    static func webURL(_ hash: String) -> URL {
        URL(string: base.absoluteString + "#/" + hash)!
    }

    /// Rede primeiro; sem rede, usa a última cópia salva. `soCache` lê só o disco.
    static func carregar<T: Decodable>(_ caminho: String, como: T.Type, soCache: Bool = false) async throws -> T {
        let local = arquivoLocal(caminho)
        if !soCache {
            do {
                var req = URLRequest(url: base.appendingPathComponent(caminho))
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.timeoutInterval = 15
                let (dados, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    let valor = try JSONDecoder.nr.decode(T.self, from: dados)
                    try? dados.write(to: local, options: .atomic)
                    return valor
                }
            } catch {
                // cai para o cache abaixo
            }
        }
        let dados = try Data(contentsOf: local)
        return try JSONDecoder.nr.decode(T.self, from: dados)
    }

    static func indice(soCache: Bool = false) async throws -> Indice {
        try await carregar("data/index.json", como: Indice.self, soCache: soCache)
    }

    static func fontes(soCache: Bool = false) async throws -> [String: Fonte] {
        let doc = try await carregar("data/fontes.json", como: FontesDoc.self, soCache: soCache)
        return Dictionary(uniqueKeysWithValues: doc.fontes.map { ($0.id, $0) })
    }

    static func colecao(_ arquivo: String, soCache: Bool = false) async throws -> Colecao {
        try await carregar(arquivo, como: Colecao.self, soCache: soCache)
    }
}
