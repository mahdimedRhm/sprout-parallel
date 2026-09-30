import Foundation

/// Command-palette matching: every whitespace-separated token of the query must
/// appear (case-insensitive) in the title.
public enum PaletteMatcher {
    public static func matches(_ title: String, query: String) -> Bool {
        let haystack = title.lowercased()
        return tokens(query).allSatisfy { haystack.contains($0) }
    }

    /// Matching items: titles starting with the first token first, then the
    /// rest, each group in the original (catalog) order.
    public static func order<T>(_ items: [T], query: String, title: (T) -> String) -> [T] {
        let matching = items.filter { matches(title($0), query: query) }
        guard let first = tokens(query).first else { return matching }
        let leading = matching.filter { title($0).lowercased().hasPrefix(first) }
        let rest = matching.filter { !title($0).lowercased().hasPrefix(first) }
        return leading + rest
    }

    private static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
