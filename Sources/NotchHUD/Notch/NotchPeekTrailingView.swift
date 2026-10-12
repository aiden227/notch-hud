import SwiftUI

struct NotchPeekTrailingView: View {
    let store: SessionStore

    var body: some View {
        if store.total > 0 {
            Text("\(store.total) sessions")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NotchDesign.text(0.52))
                .monospacedDigit()
                .fixedSize()
        }
    }
}
