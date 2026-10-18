import SwiftUI
import UIKit

// Mesmas cores do app web: esquerda vermelha, direita azul, disputa laranja, ações em verde-petróleo.
extension Color {
    init(claro: UInt32, escuro: UInt32) {
        self = Color(UIColor { t in UIColor(hex: t.userInterfaceStyle == .dark ? escuro : claro) })
    }

    static let nrFundo = Color(claro: 0xF3F4EF, escuro: 0x16181D)
    static let nrCartao = Color(claro: 0xFBFBF8, escuro: 0x1D2027)
    static let nrTinta = Color(claro: 0x1B2030, escuro: 0xECEDF0)
    static let nrMudo = Color(claro: 0x5E6371, escuro: 0xA0A4AE)
    static let nrLinha = Color(claro: 0xD8DACF, escuro: 0x30343C)
    static let nrSuave = Color(claro: 0xE7E9E1, escuro: 0x252932)
    static let nrAcao = Color(claro: 0x1F5C55, escuro: 0x7FD0C3)

    static let nrEsquerda = Color(claro: 0xC0392B, escuro: 0xF0705F)
    static let nrCentro = Color(claro: 0x7B8693, escuro: 0x9AA5B2)
    static let nrDireita = Color(claro: 0x2F5FB3, escuro: 0x6E9BEF)
    static let nrFora = Color(claro: 0x7A4FB0, escuro: 0xB394EE)

    static let nrFato = Color(claro: 0x2C7A4B, escuro: 0x5CC48A)
    static let nrInferencia = Color(claro: 0x8A6D12, escuro: 0xD9B44E)
    static let nrDisputa = Color(claro: 0xB4530A, escuro: 0xF29A4A)

    static func lado(_ l: Lado?) -> Color {
        switch l {
        case .esquerda: return .nrEsquerda
        case .centro: return .nrCentro
        case .direita: return .nrDireita
        case nil: return .nrLinha
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    static func manchete(_ size: CGFloat, peso: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: peso, design: .serif)
    }
    static let rotulo = Font.system(size: 11, weight: .semibold)
}

/// Barra horizontal com a proporção esquerda / centro / direita.
struct BarraEspectro: View {
    var cobertura: Cobertura
    var altura: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let total = max(cobertura.n, 1)
            let espaco: CGFloat = cobertura.n > 0 ? 2 : 0
            let util = max(geo.size.width - espaco * 2, 0)
            HStack(spacing: espaco) {
                if cobertura.n == 0 {
                    Rectangle().fill(Color.nrSuave)
                } else {
                    Rectangle().fill(Color.nrEsquerda).frame(width: util * CGFloat(cobertura.e) / CGFloat(total))
                    Rectangle().fill(Color.nrCentro).frame(width: util * CGFloat(cobertura.c) / CGFloat(total))
                    Rectangle().fill(Color.nrDireita).frame(width: util * CGFloat(cobertura.d) / CGFloat(total))
                }
            }
        }
        .frame(height: altura)
        .clipShape(RoundedRectangle(cornerRadius: altura / 2))
        .accessibilityElement()
        .accessibilityLabel("Esquerda \(cobertura.pE)%, centro \(cobertura.pC)%, direita \(cobertura.pD)%")
    }
}

struct Percentuais: View {
    var cobertura: Cobertura

    var body: some View {
        HStack(spacing: 12) {
            item(.nrEsquerda, "Esq. \(cobertura.pE)%")
            item(.nrCentro, "Centro \(cobertura.pC)%")
            item(.nrDireita, "Dir. \(cobertura.pD)%")
        }
        .font(.caption)
        .foregroundStyle(Color.nrMudo)
        .monospacedDigit()
    }

    private func item(_ cor: Color, _ texto: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(cor).frame(width: 8, height: 8)
            Text(texto)
        }
    }
}
