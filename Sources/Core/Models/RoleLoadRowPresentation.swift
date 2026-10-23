import Foundation

/// Presentation state stays keyed by role, independent of polling and task lanes.
struct RoleLoadRowPresentation {
    private(set) var collapsedRoles: Set<String> = []

    mutating func toggle(_ role: String) {
        if !collapsedRoles.insert(role).inserted { collapsedRoles.remove(role) }
    }

    func isCollapsed(_ role: String) -> Bool { collapsedRoles.contains(role) }

    static func height(laneCount: Int, openCount: Int, collapsed: Bool) -> CGFloat {
        if collapsed { return 44 }
        return max(104, CGFloat(max(1, laneCount)) * 32 + CGFloat(openCount) * 32 + 8)
    }
}
