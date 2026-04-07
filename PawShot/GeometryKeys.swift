import SwiftUI

struct HighlightAnchor: Equatable {
    var rect: CGRect = .zero
}

struct HighlightPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: HighlightAnchor] = [:]

    static func reduce(value: inout [Int: HighlightAnchor], nextValue: () -> [Int: HighlightAnchor]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
