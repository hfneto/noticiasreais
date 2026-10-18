import Foundation
import Security

/// Token do GitHub guardado no Keychain. Só quem tem o token (o dono do app) pede buscas novas.
enum Chaveiro {
    private static let servico = "com.hfneto.noticiasreais.github"

    static func ler() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func salvar(_ token: String) {
        apagar()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico,
                                kSecValueData as String: Data(token.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func apagar() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico]
        SecItemDelete(q as CFDictionary)
    }
}

struct IssueBusca: Decodable, Identifiable {
    var number: Int
    var title: String
    var createdAt: String
    var pullRequest: PR?
    var id: Int { number }
    var assunto: String {
        title.replacingOccurrences(of: #"^\s*busca:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    struct PR: Decodable {}
}

enum GitHub {
    enum Falha: LocalizedError {
        case semToken, recusado(Int)
        var errorDescription: String? {
            switch self {
            case .semToken: return "Cadastre o token do GitHub em Ajustes para pedir buscas."
            case .recusado(401), .recusado(403): return "O GitHub recusou o token. Confira se ele vale para o repositório e tem permissão de escrita em Issues."
            case .recusado(let c): return "O GitHub respondeu com erro \(c). Tente de novo em instantes."
            }
        }
    }

    private static let api = URL(string: "https://api.github.com/repos/\(Repositorio.repo)/issues")!

    private static func requisicao(_ url: URL, metodo: String = "GET") -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = metodo
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let t = Chaveiro.ler() { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }

    /// Issues "busca: ..." abertas que ainda não viraram busca publicada.
    static func fila(feitas: Set<Int>) async -> [IssueBusca]? {
        var comp = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        comp.queryItems = [.init(name: "state", value: "open"), .init(name: "per_page", value: "50")]
        guard let resposta = try? await URLSession.shared.data(for: requisicao(comp.url!)),
              (resposta.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let issues = try? dec.decode([IssueBusca].self, from: resposta.0) else { return nil }
        return issues.filter {
            $0.pullRequest == nil && $0.title.lowercased().hasPrefix("busca:") && !feitas.contains($0.number)
        }
    }

    static func pedirBusca(_ assunto: String) async throws {
        guard Chaveiro.ler() != nil else { throw Falha.semToken }
        var r = requisicao(api, metodo: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": "busca: \(assunto)",
            "body": "Pedido feito pelo app iOS.",
        ])
        let (_, resp) = try await URLSession.shared.data(for: r)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 201 else { throw Falha.recusado(codigo) }
    }
}
