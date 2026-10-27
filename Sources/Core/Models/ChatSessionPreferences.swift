import Foundation
struct ChatSessionPreferences: Codable, Equatable {
 let model: String?
 let thinkingLevel: String?
 let configured: Bool
 static func validThinking(_ selected: String?, available: [String]) -> String? {
  selected.flatMap { available.contains($0) ? $0 : nil }
 }
 static func thinkingTitle(_ level: String) -> String {
  switch level {
  case "off": "Выключены"
  case "minimal": "Минимальный"
  case "low": "Низкий"
  case "medium": "Средний"
  case "high": "Высокий"
  case "xhigh": "Очень высокий"
  case "max": "Максимальный"
  default: level
  }
 }
}
