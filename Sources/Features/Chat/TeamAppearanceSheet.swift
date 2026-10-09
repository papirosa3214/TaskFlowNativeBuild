import SwiftUI

struct TeamAppearanceSheet: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var selected = "current"
    @Environment(\.dismiss) private var dismiss
    private let roles = ["researcher", "analyst", "builder", "architect", "code_orchestrator", "secretary", "critic_verifier", "qa", "designer"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(TeamAvatarAppearance.allCases) { appearance in
                    Button {
                        selected = appearance.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(appearance.title)
                                Spacer()
                                if selected == appearance.rawValue { Image(systemName: "checkmark") }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                                ForEach(roles, id: \.self) { role in
                                    if let asset = RoleAvatarAsset.imageName(for: role, appearance: appearance) {
                                        Image(asset).resizable().scaledToFill()
                                            .frame(width: 48, height: 48).clipShape(Circle())
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("team-appearance-" + appearance.rawValue)
                    .accessibilityValue(selected == appearance.rawValue ? "Выбран" : "Не выбран")
                }
            }
            .navigationTitle("Внешний вид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
