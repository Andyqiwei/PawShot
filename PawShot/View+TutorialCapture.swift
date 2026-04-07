import SwiftUI

extension View {
    func captureRect(_ id: Int) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HighlightPreferenceKey.self,
                    value: [id: HighlightAnchor(rect: proxy.frame(in: .global))]
                )
            }
        )
    }
}
