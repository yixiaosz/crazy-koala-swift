// Components/YellowBar.swift
// Simple yellow header bar and title bar variant (dev-plan §7.1)

import SwiftUI

struct YellowBar: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.poppins(.bold, size: 22))
                .foregroundColor(.black)
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.yellow)
    }
}

struct YellowTitleBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                        .font(.poppins(.medium, size: 16))
                }
                .foregroundColor(.black)
            }
            .padding(.leading, 16)

            Spacer()

            Text(title)
                .font(.poppins(.bold, size: 22))
                .foregroundColor(.black)

            Spacer()

            // Invisible spacer to balance the Back button
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
                    .font(.poppins(.medium, size: 16))
            }
            .opacity(0)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color.yellow)
    }
}
