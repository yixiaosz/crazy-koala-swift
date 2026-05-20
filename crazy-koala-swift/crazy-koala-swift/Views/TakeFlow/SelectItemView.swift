// Views/TakeFlow/SelectItemView.swift
// Grid of unretrieved items for the Take flow (dev-plan §6.5)

import SwiftUI

struct SelectItemView: View {
    @EnvironmentObject var appState: AppState

    @State private var items: [(name: String, photoPath: String)] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: "Select an Item to Take") {
                appState.sessionLog.log(.tapBack, details: ["from": "SelectItemView"])
                appState.goBack()
            }

            if items.isEmpty {
                Spacer()
                Text("No items available to take.")
                    .font(.poppins(.medium, size: 18))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items, id: \.name) { item in
                            Button {
                                selectItem(name: item.name)
                            } label: {
                                VStack(spacing: 8) {
                                    let absPath = DatabaseService.resolveAbsolutePath(item.photoPath)
                                    if let uiImage = UIImage(contentsOfFile: absPath) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 150, height: 150)
                                            .clipped()
                                            .cornerRadius(8)
                                    } else {
                                        Rectangle()
                                            .fill(Color(.systemGray5))
                                            .frame(width: 150, height: 150)
                                            .cornerRadius(8)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.secondary)
                                            )
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
            appState.sessionLog.log(.viewAppear, details: ["view": "SelectItemView"])
            loadItems()
        }
    }

    private func loadItems() {
        do {
            items = try appState.itemStore.fetchUnretrievedItems()
        } catch {
            print("[SelectItemView] Failed to fetch items: \(error)")
        }
    }

    private func selectItem(name: String) {
        appState.sessionLog.log(.selectItem, details: ["name": name])
        do {
            if let item = try appState.itemStore.fetchItemDetails(name: name) {
                appState.currentItem = item
                appState.navigate(to: .viewDeposit)
            }
        } catch {
            print("[SelectItemView] Failed to fetch item details: \(error)")
        }
    }
}
