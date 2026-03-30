import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var vm: FeedViewModel
    @AppStorage("showPreviews") private var showPreviews = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !vm.featured.isEmpty {
                        FeaturedStrip(items: vm.featured)
                            .padding(.bottom, 8)
                    }

                    FilterBar(selection: $vm.filter)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    LazyVStack(spacing: 0) {
                        ForEach(vm.filtered) { item in
                            NavigationLink(value: item) {
                                FeedItemRow(item: item, showPreview: showPreviews)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }
            }
            .navigationTitle("Grindstone")
            .navigationDestination(for: FeedItem.self) { item in
                DetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPreviews.toggle()
                    } label: {
                        Image(systemName: showPreviews ? "text.below.photo" : "list.bullet")
                    }
                }
            }
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView("Loading…")
                }
            }
            .task {
                if vm.items.isEmpty {
                    await vm.refresh()
                }
            }
        }
    }
}

#Preview {
    FeedView()
        .environmentObject({
            let vm = FeedViewModel()
            vm.items = FeedItem.mock
            return vm
        }())
}
