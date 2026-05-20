// Views/Memories/GalleryView.swift
// Grid of completed memories (both deposit and taken photos exist) (dev-plan §6.7)

import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var appState: AppState

    @State private var items: [Item] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: "Happy Memories") {
                appState.sessionLog.log(.tapBack, details: ["from": "GalleryView"])
                appState.goBack()
            }

            if items.isEmpty {
                Spacer()
                Text("No memories yet.")
                    .font(.poppins(.medium, size: 18))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items, id: \.id) { item in
                            Button {
                                appState.sessionLog.log(.selectItem, details: ["name": item.name])
                                appState.currentItem = item
                                appState.navigate(to: .detail)
                            } label: {
                                VStack(spacing: 8) {
                                    // Show taken photo (§6.7)
                                    if let photoPath = item.takenPhotoPath {
                                        let absPath = DatabaseService.resolveAbsolutePath(photoPath)
                                        if let uiImage = UIImage(contentsOfFile: absPath) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 150, height: 150)
                                                .clipped()
                                                .cornerRadius(8)
                                        } else {
                                            photoPlaceholder
                                        }
                                    } else {
                                        photoPlaceholder
                                    }

                                    Text(item.name)
                                        .font(.poppins(.medium, size: 14))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "GalleryView"])
            loadItems()
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: 150, height: 150)
            .cornerRadius(8)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            )
    }

    private func loadItems() {
        do {
            items = try appState.itemStore.fetchAllItems()
        } catch {
            print("[GalleryView] Failed to fetch items: \(error)")
        }
    }
}
