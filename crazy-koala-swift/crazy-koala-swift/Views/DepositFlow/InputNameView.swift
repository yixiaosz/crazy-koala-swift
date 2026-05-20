// Views/DepositFlow/InputNameView.swift
// Text input for item name with validation (dev-plan §6.2)

import SwiftUI

struct InputNameView: View {
    @EnvironmentObject var appState: AppState

    @State private var itemName: String = ""
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: "Name Your Item") {
                appState.sessionLog.log(.tapBack, details: ["from": "InputNameView"])
                appState.goBack()
            }

            Spacer()

            VStack(spacing: 24) {
                Text("Enter a name\nfor the item you would like to deposit")
                    .font(.poppins(.medium, size: 20))
                    .multilineTextAlignment(.center)

                TextField("Item name", text: $itemName)
                    .font(.poppins(.regular, size: 18))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                RoundedButton(title: "Next") {
                    validateAndProceed()
                }
            }

            Spacer()
        }
        .navigationBarHidden(true)
        .alert("Invalid Name", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "InputNameView"])
        }
    }

    // MARK: - Validation (§6.2)

    private func validateAndProceed() {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Not empty
        guard !trimmed.isEmpty else {
            showValidationError("Please enter a name for your item.")
            return
        }

        // Max 50 characters
        guard trimmed.count <= 50 else {
            showValidationError("Name must be 50 characters or fewer.")
            return
        }

        // Allowed characters: alphanumeric, spaces, hyphens, underscores
        let allowedPattern = "^[a-zA-Z0-9 \\-_]+$"
        guard trimmed.range(of: allowedPattern, options: .regularExpression) != nil else {
            showValidationError("Name can only contain letters, numbers, spaces, hyphens, and underscores.")
            return
        }

        // No filesystem-unsafe characters (extra safety)
        let unsafeChars: [String] = ["/", "\\", "..", ":"]
        for c in unsafeChars {
            if trimmed.contains(c) {
                showValidationError("Name contains an unsafe character: \(c)")
                return
            }
        }

        // Duplicate check: folder data/{name} must not exist
        let dataDir = DatabaseService.documentsURL.appendingPathComponent("data").appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: dataDir.path) {
            showValidationError("An item with this name already exists. Please choose a different name.")
            return
        }

        // Validation passed
        appState.sessionLog.log(.inputName, details: ["name": trimmed])
        appState.sessionLog.log(.tapNext, details: ["from": "InputNameView"])

        // Create a temporary Item to carry the name forward
        appState.currentItem = Item(name: trimmed)
        appState.navigate(to: .depositPrompt)
    }

    private func showValidationError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
