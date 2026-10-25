import SwiftUI

/// System list row actions. Apple owns the gesture, surface and button shapes.
struct DirectorySwipeRow<Content: View>: View {
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void
    var deleteIcon = "archivebox"
    var deleteLabel = "В архив"
    var deleteIdentifier = "directory.swipe.delete"
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: deleteIcon)
                }
                .tint(Color.tfSwipeDelete)
                .accessibilityLabel(deleteLabel)
                .accessibilityIdentifier(deleteIdentifier)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .tint(Color.tfSwipeEdit)
                    .accessibilityLabel("Изменить")
                }
            }
    }
}
