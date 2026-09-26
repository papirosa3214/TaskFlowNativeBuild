// Sources/Core/Networking/ServiceTicketMarkdownParser.swift
import Foundation

/// Разбирает markdown-сводку `.110` — docs/2026-09-27-notifications-service-tickets-spec.md.
/// Метаданные и блок «Сводка» — живой, проверенный формат. Блок
/// «## Итог по устранению» — Phase 4 backend, на 27.09.2026 сервер его
/// ещё не пишет; парсинг best-effort по эталонному шаблону, перепроверить
/// на первом живом файле.
public enum ServiceTicketMarkdownParser {
    public static func parse(_ raw: String) -> ServiceTicketDetail? {
        let lines = raw.components(separatedBy: .newlines)

        guard let title = lines.first(where: { $0.hasPrefix("# ") })?
            .dropFirst(2).trimmingCharacters(in: .whitespaces) else { return nil }

        func metaValue(_ key: String) -> String? {
            guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- \(key):") }) else { return nil }
            return line.split(separator: ":", maxSplits: 1).dropFirst().first
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard let when = metaValue("когда"),
              let from = metaValue("от кого"),
              let level = metaValue("уровень"),
              let alarmRaw = metaValue("тревога") else { return nil }
        let isAlarm = alarmRaw.lowercased() == "да"

        let summaryText = extractFencedBlock(lines, afterHeading: "## Сводка")
        let notWorkingText = extractNotWorkingLine(summaryText)
        let diagnosticTaskId = firstTaskLink(in: summaryText)
        let resolutionItems = extractResolutionItems(lines)

        return ServiceTicketDetail(
            title: title, when: when, from: from, level: level, isAlarm: isAlarm,
            summaryText: summaryText, notWorkingText: notWorkingText,
            diagnosticTaskId: diagnosticTaskId, resolutionItems: resolutionItems
        )
    }

    /// `tf://task/<id>` встречается как обычный текст внутри markdown — не
    /// системная URL-схема, приложение сам разбирает и открывает через
    /// внутреннюю навигацию (`route = .taskDetail(taskID:)`), регистрировать
    /// `tf://` в Info.plist не нужно.
    static func firstTaskLink(in text: String) -> String? {
        guard let range = text.range(of: #"tf://task/([\w-]+)"#, options: .regularExpression) else { return nil }
        return String(text[range]).replacingOccurrences(of: "tf://task/", with: "")
    }

    private static func extractFencedBlock(_ lines: [String], afterHeading: String) -> String {
        guard let headingIdx = lines.firstIndex(where: { $0.hasPrefix(afterHeading) }) else { return "" }
        let rest = lines[(headingIdx + 1)...]
        guard let fenceStart = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else { return "" }
        let afterFence = lines[(fenceStart + 1)...]
        guard let fenceEnd = afterFence.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else { return "" }
        return lines[(fenceStart + 1)..<fenceEnd].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractNotWorkingLine(_ summary: String) -> String? {
        let lines = summary.components(separatedBy: .newlines)
        guard let idx = lines.firstIndex(where: { $0.contains("Не отработали в штатном режиме") }) else { return nil }
        return lines[(idx + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Собирает пункты "## Итог по устранению" — каждый пункт начинается с
    /// "- " и может продолжаться на нескольких отступленных строках (см.
    /// вариант "нужно ваше решение..." в шаблоне), пока не встретится
    /// следующий "- " или конец блока.
    private static func extractResolutionItems(_ lines: [String]) -> [ServiceTicketResolutionItem] {
        guard let headingIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## Итог по устранению") }) else {
            return []
        }
        var blocks: [String] = []
        var current: String?
        for line in lines[(headingIdx + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") { break }
            if trimmed.hasPrefix("- ") {
                if let c = current { blocks.append(c) }
                current = String(trimmed.dropFirst(2))
            } else if !trimmed.isEmpty, current != nil {
                current! += " " + trimmed
            } else if trimmed.isEmpty, current != nil, !blocks.contains(current!) {
                // Пустая строка внутри многострочного пункта — ещё не конец,
                // граница — следующий "- " или "##"; продолжаем накопление.
                continue
            }
        }
        if let c = current { blocks.append(c) }

        return blocks.compactMap { block -> ServiceTicketResolutionItem? in
            guard let dashRange = block.range(of: " — (") else { return nil }
            let problem = String(block[block.startIndex..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            var statusText = String(block[dashRange.upperBound...])
            if statusText.hasSuffix(")") { statusText.removeLast() }
            let taskId = firstTaskLink(in: block)

            if statusText == "исправлено" {
                return ServiceTicketResolutionItem(problem: problem, status: .fixed, taskId: taskId)
            }
            if statusText.contains("нужно ваше решение") {
                let options = extractNumberedOptions(statusText)
                return ServiceTicketResolutionItem(problem: problem, status: .needsDecision(options: options), taskId: taskId)
            }
            if statusText.hasPrefix("не исправлено:") {
                let reason = statusText.replacingOccurrences(of: "не исправлено:", with: "").trimmingCharacters(in: .whitespaces)
                return ServiceTicketResolutionItem(problem: problem, status: .unresolved(reason: reason), taskId: taskId)
            }
            return nil
        }
    }

    /// "1) ... 2) ... 3) ... 4) свой вариант" → ["...", "...", "..."] (без пункта 4 — он всегда отдельное поле ввода в модалке).
    private static func extractNumberedOptions(_ text: String) -> [String] {
        let pattern = #"(\d+)\)\s*([^0-9)]+?)(?=\s*\d+\)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var options: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let numberRange = Range(match.range(at: 1), in: text),
                  let textRange = Range(match.range(at: 2), in: text) else { return }
            let number = Int(text[numberRange]) ?? 0
            guard number <= 3 else { return } // "4) свой вариант" — не предложенный вариант
            let value = text[textRange].trimmingCharacters(in: CharacterSet(charactersIn: " ,)"))
            if !value.isEmpty { options.append(value) }
        }
        return options
    }
}
