import SwiftUI

/// Строка расхода хода роли — над кнопками «копировать / ответвление»
/// (владелец 19.10.2026): скорость, вход, выход, кэш, ориентировочная цена.
/// Чего модель не сообщила — того в строке нет.
struct RoleTurnUsageRow: View {
    let usage: RoleTurnUsage

    var body: some View {
        Text(parts.joined(separator: " · "))
            .tfText(.caption)
            .monospacedDigit()
            .foregroundStyle(Color.tfSub)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel("Расход ответа: " + parts.joined(separator: ", "))
            .accessibilityIdentifier("chat.message.usage")
    }

    private var parts: [String] {
        var out: [String] = []
        if let speed = usage.tokensPerSecond { out.append("\(Int(speed.rounded())) ток/с") }
        // Владелец 20.10.2026: сумма входа за ход (2 млн на 13 шагах) читалась
        // как ошибка — показываем размер беседы на шаг и число шагов.
        if let context = usage.context {
            out.append("контекст \(Self.tokens(context))")
        } else {
            out.append("вход \(Self.tokens(usage.input + usage.cacheRead + usage.cacheWrite))")
        }
        out.append("выход \(Self.tokens(usage.output))")
        if let hit = usage.cacheHitRatio, usage.cacheRead > 0 {
            out.append("кэш \(Int((hit * 100).rounded()))%")
        }
        if let calls = usage.calls, calls > 1 { out.append("\(calls) \(Self.stepsWord(calls))") }
        if let cost = usage.costUSD, cost > 0 { out.append(Self.cost(cost)) }
        return out
    }

    static func tokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1f тыс", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.1f млн", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",")
    }

    static func stepsWord(_ n: Int) -> String {
        let d = n % 10, h = n % 100
        if d == 1 && h != 11 { return "шаг" }
        if (2...4).contains(d) && !(12...14).contains(h) { return "шага" }
        return "шагов"
    }

    static func cost(_ usd: Double) -> String {
        if usd < 0.01 { return "≈ <$0,01" }
        return "≈ $" + String(format: "%.2f", usd).replacingOccurrences(of: ".", with: ",")
    }
}
