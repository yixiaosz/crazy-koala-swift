// Components/RoundedButton.swift
// Reusable button with black background, white Poppins text, rounded corners (dev-plan §7.2)

import SwiftUI

struct RoundedButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.poppins(.medium, size: 18))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.black)
                .cornerRadius(12)
        }
    }
}
