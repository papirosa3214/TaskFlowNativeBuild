import Foundation

/// Empty-state backdrop is shown only after a successful load of an empty tab.
enum PlannerBackdropVisibility {
    static func isVisible(isLoading: Bool, hasError: Bool, visibleTaskCount: Int) -> Bool {
        !isLoading && !hasError && visibleTaskCount == 0
    }
}
