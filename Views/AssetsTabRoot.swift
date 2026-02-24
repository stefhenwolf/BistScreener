import SwiftUI

struct AssetsTabRoot: View {
    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            AssetsView()
        }
        .navigationTitle("Varlıklarım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TVTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
