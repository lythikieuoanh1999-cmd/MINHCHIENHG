import SwiftUI

enum Theme {
    static let accent = Color(red: 0.31, green: 0.55, blue: 1.0)     // xanh dương KENIOS
    static let purple = Color(red: 0.65, green: 0.45, blue: 0.95)
}

func providerColor(_ id: String) -> Color {
    switch id {
    case "gemini":      return .blue
    case "openai":      return .green
    case "anthropic":   return Theme.purple
    case "groq":        return .green
    case "deepseek":    return .yellow
    case "xai":         return .red
    case "mistral":     return .pink
    case "openrouter":  return .teal
    case "perplexity":  return .cyan
    case "qwen":        return .orange
    case "moonshot":    return .indigo
    default:            return .gray
    }
}

func categoryIcon(_ category: String?) -> String {
    switch category {
    case "image":    return "photo"
    case "code":     return "chevron.left.forwardslash.chevron.right"
    case "document": return "doc.text"
    default:         return "doc"
    }
}

func humanSize(_ bytes: Int?) -> String {
    guard let b = bytes else { return "" }
    if b < 1024 { return "\(b) B" }
    if b < 1024 * 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
    return String(format: "%.1f MB", Double(b) / 1024 / 1024)
}
