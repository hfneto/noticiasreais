import Foundation

enum Lado: String, CaseIterable, Hashable {
    case esquerda, centro, direita

    init?(vies: String?) {
        switch vies {
        case "esquerda", "centro_esquerda": self = .esquerda
        case "centro": self = .centro
        case "centro_direita", "direita": self = .direita
        default: return nil
        }
    }

    var nome: String {
        switch self {
        case .esquerda: return "Esquerda"
        case .centro: return "Centro"
        case .direita: return "Direita"
        }
    }

    var curto: String {
        switch self {
        case .esquerda: return "Esq."
        case .centro: return "Centro"
        case .direita: return "Dir."
        }
    }
}

enum Vies {
    static let nomes: [String: String] = [
        "esquerda": "Esquerda", "centro_esquerda": "Centro-esquerda", "centro": "Centro",
        "centro_direita": "Centro-direita", "direita": "Direita", "nao_classificado": "Não classificado",
    ]
    static let ordem = ["esquerda", "centro_esquerda", "centro", "centro_direita", "direita", "nao_classificado"]

    /// Viés usado para uma matéria: o do veículo cadastrado ou, sem isso, a avaliação da própria matéria.
    static func daMateria(_ m: Materia, fontes: [String: Fonte]) -> (vies: String, porMateria: Bool) {
        if let id = m.fonte, let f = fontes[id], f.vies != "nao_classificado" {
            return (f.vies, false)
        }
        return (m.viesMateria ?? "nao_classificado", true)
    }

    static func estrangeira(_ m: Materia, historia h: Historia, fontes: [String: Fonte]) -> Bool {
        guard h.escopo == "brasil", let id = m.fonte, let f = fontes[id] else { return false }
        return f.pais != "BR"
    }
}

/// Mesma regra do app web (index.html → cobertura()).
struct Cobertura: Hashable {
    var e = 0, c = 0, d = 0, estrangeiras = 0, n = 0
    var gov = 0, neutro = 0, op = 0

    var pE: Int { n == 0 ? 0 : Int((Double(e) / Double(n) * 100).rounded()) }
    var pD: Int { n == 0 ? 0 : Int((Double(d) / Double(n) * 100).rounded()) }
    var pC: Int { n == 0 ? 0 : 100 - pE - pD }

    /// Lado que quase não está cobrindo a história (≤ 20% contra ≥ 40% do outro).
    var pontoCego: Lado? {
        guard n >= 4 else { return nil }
        let fe = Double(e) / Double(n), fd = Double(d) / Double(n)
        if fe <= 0.2 && fd >= 0.4 { return .esquerda }
        if fd <= 0.2 && fe >= 0.4 { return .direita }
        return nil
    }

    init() {}

    init(_ h: Historia, fontes: [String: Fonte]) {
        for m in h.materias ?? [] {
            if m.tipo == "fonte_primaria" || m.tipo == "checagem" { continue }
            switch Lado(vies: Vies.daMateria(m, fontes: fontes).vies) {
            case .esquerda: e += 1; n += 1
            case .centro: c += 1; n += 1
            case .direita: d += 1; n += 1
            case nil: break
            }
            if Vies.estrangeira(m, historia: h, fontes: fontes) { estrangeiras += 1 }
            switch m.enquadramento {
            case "pro_governo": gov += 1
            case "oposicao": op += 1
            case "neutro": neutro += 1
            default: break
            }
        }
    }
}
