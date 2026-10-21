import SwiftUI

/// Кадрирование портрета роли: чем и насколько картинка увеличена внутри
/// круглого кружка и куда сдвинута.
///
/// Зачем оно владельцу 10.10.2026: вырезать картинку под круг вручную он не
/// хочет («слепой крот»), а руками подвинуть её в кружке — хочет. Здесь
/// хранится ровно то, что он выставил, и применяется ко всем местам, где
/// рисуется портрет этой роли.
///
/// Ключи живут в UserDefaults, фото — в Application Support: картинка может
/// весить мегабайты, в UserDefaults её класть нельзя.
enum AvatarCrop {
    /// Форма кружка. Круг — как было; прямоугольник со скруглением — по выбору
    /// владельца (10.10.2026: «не обязательно круг, может быть квадрат»).
    enum Shape: String, Codable, CaseIterable, Identifiable {
        case circle, rounded
        var id: String { rawValue }
        var title: String { self == .circle ? "Круг" : "Квадрат" }
        var corner: CGFloat { self == .circle ? .infinity : TFRadius.md }
    }

    struct Value: Codable, Equatable {
        var scale: Double = 1
        var dx: Double = 0
        var dy: Double = 0
        /// Своё фото вместо вшитого портрета; `nil` — портрет роли.
        var photo: String?
        var shape: Shape = .circle
    }

    static let defaultValue = Value()

    private static func key(_ role: String) -> String { "avatarCrop.\(role)" }
    private static var photosDir: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func value(for role: String) -> Value {
        guard let data = UserDefaults.standard.data(forKey: key(role)),
              let v = try? JSONDecoder().decode(Value.self, from: data) else { return defaultValue }
        return v
    }

    static func save(_ value: Value, for role: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key(role))
        }
    }

    static func reset(for role: String) {
        UserDefaults.standard.removeObject(forKey: key(role))
    }

    /// Сохранить выбранное фото и вернуть путь к файлу.
    @discardableResult
    static func storePhoto(_ data: Data, for role: String) -> String? {
        let url = photosDir.appendingPathComponent("\(role).jpg")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url.lastPathComponent
    }

    static func photoURL(_ name: String) -> URL { photosDir.appendingPathComponent(name) }

    /// Человеческое название роли — для списка в редакторе.
    static func roleTitle(_ role: String) -> String {
        switch role {
        case "researcher": return "Исследователь"
        case "analyst": return "Аналитик"
        case "builder": return "Разработчик"
        case "architect": return "Архитектор"
        case "code_orchestrator", "orchestrator": return "Оркестратор"
        case "secretary": return "Помощник владельца"
        case "critic_verifier": return "Критик"
        case "qa": return "QA"
        case "designer": return "Дизайнер"
        case "infra_engineer": return "Инженер .110"
        default: return role
        }
    }
}