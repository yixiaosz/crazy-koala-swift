// App/BundleImage.swift
// Helper to load images from the app bundle (not Asset Catalog)

import SwiftUI

struct BundleImage: View {
    let name: String
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil

    var body: some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
    }
}
