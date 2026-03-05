import SwiftUI

struct ChatsSplitLayout<Sidebar: View, Detail: View>: View {
    let detailID: UUID?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationSplitView {
            NavigationStack {
                sidebar()
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 480)
            #endif
        } detail: {
            NavigationStack {
                detail()
            }
            .id(detailID)
        }
    }
}
