import SwiftUI

struct HighlightAnchor: Equatable {
    var rect: CGRect = .zero
}

struct HighlightPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: HighlightAnchor] = [:]

    static func reduce(value: inout [Int: HighlightAnchor], nextValue: () -> [Int: HighlightAnchor]) {
        let incoming = nextValue()
        for (key, anchor) in incoming {
            if let existing = value[key] {
                value[key] = HighlightAnchor(rect: unionNonEmpty(existing.rect, anchor.rect))
            } else {
                value[key] = anchor
            }
        }
    }

    /// Combines frames from multiple `.captureRect(id)` on the same id (e.g. list header + rows).
    private static func unionNonEmpty(_ a: CGRect, _ b: CGRect) -> CGRect {
        let aOK = a.width > 1 && a.height > 1
        let bOK = b.width > 1 && b.height > 1
        switch (aOK, bOK) {
        case (true, true): return a.union(b)
        case (true, false): return a
        case (false, true): return b
        default: return .zero
        }
    }
}
