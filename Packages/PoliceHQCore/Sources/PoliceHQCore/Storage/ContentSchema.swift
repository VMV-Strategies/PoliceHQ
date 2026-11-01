import Foundation

/// Access to the bundled content schema (identical to schema/content_schema.sql; CI checks this).
public enum ContentSchema {
    public static var sql: String {
        guard let url = Bundle.module.url(forResource: "content_schema", withExtension: "sql"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    public static let version = 1
}
