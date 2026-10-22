import Foundation

// Espelha os JSONs publicados em data/ (ver CLAUDE.md). Chaves em snake_case são convertidas pelo decodificador.

struct Indice: Codable, Hashable {
    var atualizadoEm: String?
    var edicoes: [EdicaoMeta]
    var buscas: [BuscaMeta]
}

struct EdicaoMeta: Codable, Hashable, Identifiable {
    var data: String
    var arquivo: String
    var historias: Int
    var geradoEm: String?
    var manchete: String?
    var id: String { data }
}

struct BuscaMeta: Codable, Hashable, Identifiable {
    var slug: String
    var consulta: String
    var arquivo: String
    var historias: Int
    var geradoEm: String?
    var issue: Int?
    var id: String { slug }
}

struct Colecao: Codable, Hashable {
    var tipo: String
    var data: String?
    var slug: String?
    var consulta: String?
    var resumo: String?
    var geradoEm: String?
    var historias: [Historia]
}

struct Historia: Codable, Hashable, Identifiable {
    var id: String
    var editoria: String
    var escopo: String
    var titulo: String
    var lide: String
    var contexto: String?
    var atualizadoEm: String?
    var fatos: [Fato]?
    var inferencias: [Inferencia]?
    var emDisputa: [Disputa]?
    var enquadramentos: Enquadramentos?
    var visaoDeFora: String?
    var pontoCego: String?
    var continua: Continuacao?
    var materias: [Materia]?
}

struct Fato: Codable, Hashable { var texto: String; var base: String }
struct Continuacao: Codable, Hashable { var data: String; var id: String; var titulo: String? }
struct Inferencia: Codable, Hashable { var texto: String; var quem: String }
struct Checagem: Codable, Hashable { var nome: String; var url: String }
struct Enquadramentos: Codable, Hashable { var governo: String?; var oposicao: String? }

struct Disputa: Codable, Hashable {
    var alegacao: String
    var rotulo: String
    var explicacao: String
    var ondeCircula: String?
    var checagem: [Checagem]?
}

struct Materia: Codable, Hashable, Identifiable {
    var fonte: String?
    var veiculo: String?
    var viesMateria: String?
    var titulo: String
    var url: String
    var angulo: String?
    var tipo: String?
    var enquadramento: String?
    var data: String?
    var id: String { url }
}

struct FontesDoc: Codable {
    var tiposPropriedade: [String: String]
    var fontes: [Fonte]
}

struct Fonte: Codable, Hashable, Identifiable {
    var id: String
    var nome: String
    var dominios: [String]
    var pais: String
    var vies: String
    var propriedade: String
    var dono: String
    var base: String?
    var notas: String?
    var checagem: Bool?
    var alcance: String?
}

/// Onde uma história mora: numa edição diária ou numa busca.
enum ColRef: Hashable, Codable {
    case edicao(String)
    case busca(String)

    var webPath: String {
        switch self {
        case .edicao(let d): return "h/\(d)"
        case .busca(let s): return "b/\(s)"
        }
    }
}

enum Rota: Hashable {
    case historia(ColRef, String)
    case busca(String)
    case edicao(String)
    case fontes
    case metodo
}

extension JSONDecoder {
    static let nr: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

enum Datas {
    static let tz = TimeZone(identifier: "America/Sao_Paulo")!

    static func hoje() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    static func dia(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0.addingTimeInterval(12 * 3600) }
    }

    static func extenso(_ s: String) -> String {
        guard let d = dia(s) else { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = tz
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: d).capitalizedFirst
    }

    static func curta(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = tz
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    static func hora(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

extension String {
    var capitalizedFirst: String { self.prefix(1).uppercased() + self.dropFirst() }
}
