import Foundation
import UserNotifications

/// Aviso diário da edição. Mantém uma janela de 7 avisos agendados; quando a edição do dia já saiu,
/// o aviso de hoje (ainda pendente) passa a trazer a manchete.
enum Notificacoes {
    private static let prefixo = "edicao-"
    private static let defaults = UserDefaults(suiteName: Repositorio.grupo) ?? .standard

    static var ativas: Bool {
        get { defaults.bool(forKey: "notif.ativas") }
        set { defaults.set(newValue, forKey: "notif.ativas") }
    }

    /// Hora do aviso em minutos desde a meia-noite (padrão 6h45).
    static var minutos: Int {
        get { defaults.object(forKey: "notif.minutos") as? Int ?? 6 * 60 + 45 }
        set { defaults.set(newValue, forKey: "notif.minutos") }
    }

    static func pedirPermissao() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reagendar(manchete: (data: String, titulo: String)? = nil) async {
        let centro = UNUserNotificationCenter.current()
        let pendentes = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefixo) }
        centro.removePendingNotificationRequests(withIdentifiers: pendentes)
        guard ativas else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Datas.tz
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = Datas.tz
        fmt.dateFormat = "yyyy-MM-dd"

        for dia in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: dia, to: Date()) else { continue }
            var comp = cal.dateComponents([.year, .month, .day], from: d)
            comp.hour = minutos / 60
            comp.minute = minutos % 60
            comp.timeZone = Datas.tz
            guard let quando = cal.date(from: comp), quando > Date() else { continue }

            let chave = fmt.string(from: d)
            let conteudo = UNMutableNotificationContent()
            conteudo.title = "Edição de hoje"
            if let manchete, manchete.data == chave {
                conteudo.body = manchete.titulo
            } else {
                conteudo.body = "As histórias do dia, com todos os lados, já estão no app."
            }
            conteudo.sound = .default
            conteudo.userInfo = ["data": chave]
            let gatilho = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            try? await centro.add(UNNotificationRequest(identifier: prefixo + chave, content: conteudo, trigger: gatilho))
        }
    }

    static func atualizarManchete(indice: Indice) async {
        guard ativas else { return }
        let manchete = indice.edicoes.first.flatMap { e in e.manchete.map { (data: e.data, titulo: $0) } }
        await reagendar(manchete: manchete)
    }
}
