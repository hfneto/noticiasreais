import BackgroundTasks
import SwiftUI
import WidgetKit

@main
struct NoticiasReaisApp: App {
    @State private var modelo = AppModel()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(modelo)
                .tint(.nrAcao)
                .task { await modelo.atualizar() }
        }
        .onChange(of: fase) { _, nova in
            if nova == .background { AtualizacaoFundo.agendar() }
            if nova == .active { Task { await modelo.atualizar() } }
        }
        .backgroundTask(.appRefresh(AtualizacaoFundo.id)) {
            await AtualizacaoFundo.executar()
        }
    }
}

/// Atualização em segundo plano: baixa o índice e a edição nova, refresca o widget e põe a manchete no aviso do dia.
/// O iOS decide quando roda; por isso o aviso diário existe mesmo sem ela.
enum AtualizacaoFundo {
    static let id = "com.hfneto.noticiasreais.refresh"

    static func agendar() {
        let pedido = BGAppRefreshTaskRequest(identifier: id)
        pedido.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(pedido)
    }

    static func executar() async {
        agendar()
        guard let indice = try? await Repositorio.indice() else { return }
        _ = try? await Repositorio.fontes()
        if let atual = indice.edicoes.first {
            _ = try? await Repositorio.colecao(atual.arquivo)
        }
        WidgetCenter.shared.reloadAllTimelines()
        await Notificacoes.atualizarManchete(indice: indice)
    }
}

struct RaizView: View {
    @Environment(AppModel.self) private var modelo
    @State private var aba = 0
    @State private var caminhoHoje = NavigationPath()

    var body: some View {
        TabView(selection: $aba) {
            NavigationStack(path: $caminhoHoje) {
                FeedView()
                    .navigationDestination(for: Rota.self) { DestinoView(rota: $0) }
            }
            .tabItem { Label("Hoje", systemImage: "newspaper") }
            .tag(0)

            NavigationStack {
                BuscasView()
                    .navigationDestination(for: Rota.self) { DestinoView(rota: $0) }
            }
            .tabItem { Label("Buscas", systemImage: "magnifyingglass") }
            .tag(1)

            NavigationStack {
                SalvosView()
                    .navigationDestination(for: Rota.self) { DestinoView(rota: $0) }
            }
            .tabItem { Label("Salvos", systemImage: "bookmark") }
            .tag(2)

            NavigationStack {
                AjustesView()
                    .navigationDestination(for: Rota.self) { DestinoView(rota: $0) }
            }
            .tabItem { Label("Mais", systemImage: "ellipsis.circle") }
            .tag(3)
        }
        // noticiasreais://h/<data>/<id> e noticiasreais://b/<slug>, usados pelo widget
        .onOpenURL { url in
            let partes = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
            aba = 0
            caminhoHoje = NavigationPath()
            if partes.count == 3, partes[0] == "h" {
                caminhoHoje.append(Rota.historia(.edicao(partes[1]), partes[2]))
            } else if partes.count == 2, partes[0] == "b" {
                caminhoHoje.append(Rota.busca(partes[1]))
            }
        }
    }
}

struct DestinoView: View {
    var rota: Rota

    var body: some View {
        switch rota {
        case .historia(let ref, let id): HistoriaView(ref: ref, id: id)
        case .busca(let slug): ColecaoView(ref: .busca(slug))
        case .edicao(let data): ColecaoView(ref: .edicao(data))
        case .fontes: FontesView()
        case .metodo: MetodoView()
        }
    }
}
