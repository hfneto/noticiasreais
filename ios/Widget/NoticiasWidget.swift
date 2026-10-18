import SwiftUI
import WidgetKit

struct EntradaManchete: TimelineEntry {
    var date: Date
    var dataEdicao: String?
    var historia: Historia?
    var cobertura: Cobertura
    var totalHistorias: Int

    static let exemplo = EntradaManchete(
        date: Date(), dataEdicao: nil,
        historia: Historia(id: "exemplo", editoria: "Economia", escopo: "brasil",
                           titulo: "A manchete do dia aparece aqui", lide: "Com a proporção da cobertura por lado."),
        cobertura: { var c = Cobertura(); c.e = 3; c.c = 4; c.d = 3; c.n = 10; return c }(),
        totalHistorias: 10)
}

struct ProvedorManchete: TimelineProvider {
    func placeholder(in context: Context) -> EntradaManchete { .exemplo }

    func getSnapshot(in context: Context, completion: @escaping (EntradaManchete) -> Void) {
        if context.isPreview { completion(.exemplo); return }
        // o WidgetKit chama completion uma vez só; não há corrida real
        nonisolated(unsafe) let concluir = completion
        Task { concluir(await carregar()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaManchete>) -> Void) {
        nonisolated(unsafe) let concluir = completion
        Task {
            let entrada = await carregar()
            // tenta de novo em 2 h; perto da hora da edição o app também pede recarga
            concluir(Timeline(entries: [entrada], policy: .after(Date().addingTimeInterval(2 * 3600))))
        }
    }

    private func carregar() async -> EntradaManchete {
        guard let indice = try? await Repositorio.indice(),
              let meta = indice.edicoes.first,
              let col = try? await Repositorio.colecao(meta.arquivo),
              let h = col.historias.first else {
            return EntradaManchete(date: Date(), dataEdicao: nil, historia: nil, cobertura: Cobertura(), totalHistorias: 0)
        }
        let fontes = (try? await Repositorio.fontes()) ?? [:]
        return EntradaManchete(date: Date(), dataEdicao: meta.data, historia: h,
                               cobertura: Cobertura(h, fontes: fontes), totalHistorias: col.historias.count)
    }
}

struct VistaManchete: View {
    @Environment(\.widgetFamily) private var familia
    var entrada: EntradaManchete

    var body: some View {
        Group {
            if let h = entrada.historia {
                VStack(alignment: .leading, spacing: familia == .systemSmall ? 6 : 8) {
                    Text(rotulo).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Color.nrMudo)
                        .lineLimit(1)
                    Text(h.titulo)
                        .font(.manchete(familia == .systemSmall ? 15 : 17))
                        .foregroundStyle(Color.nrTinta)
                        .lineLimit(familia == .systemSmall ? 4 : 3)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)  // sem isso o lide toma o espaço e a manchete fica com uma linha
                    if familia != .systemSmall {
                        Text(h.lide).font(.caption).foregroundStyle(Color.nrMudo).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    BarraEspectro(cobertura: entrada.cobertura, altura: 5)
                    if familia != .systemSmall {
                        Percentuais(cobertura: entrada.cobertura)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTÍCIAS REAIS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Color.nrMudo)
                    Text("Abra o app para baixar a edição.").font(.manchete(15)).foregroundStyle(Color.nrTinta)
                }
            }
        }
        .containerBackground(Color.nrFundo, for: .widget)
        .widgetURL(url)
    }

    private var rotulo: String {
        guard let d = entrada.dataEdicao else { return "NOTÍCIAS REAIS" }
        let dia = Datas.extenso(d).components(separatedBy: ",").first ?? ""
        return familia == .systemSmall ? dia.uppercased() : "\(dia.uppercased()) · \(entrada.totalHistorias) HISTÓRIAS"
    }

    private var url: URL? {
        guard let d = entrada.dataEdicao, let h = entrada.historia else { return URL(string: "noticiasreais://") }
        return URL(string: "noticiasreais://h/\(d)/\(h.id)")
    }
}

@main
struct NoticiasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "manchete", provider: ProvedorManchete()) { VistaManchete(entrada: $0) }
            .configurationDisplayName("Manchete do dia")
            .description("A principal história da edição, com a cobertura por lado.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
