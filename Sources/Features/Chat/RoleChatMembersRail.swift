import SwiftUI

/// Столбец участников у правой кромки чата (владелец 20.10.2026, по образцу
/// стороннего мессенджера). В покое — узкий край во всю высоту свободного
/// места между шапкой и полем ввода, как закладки семьи в карточке задачи
/// (`TaskFamilyEdgeTabs`): тот же цвет листа, красноватый контур и тень.
/// Тянется влево ровно на ширину аватарки и дальше не идёт; смахнул
/// вправо — спрятался. Слева край экрана не трогаем: там системное «назад».
///
/// Тап по аватару — «@Имя» в поле ввода, кому пишем. «+» внизу — добавить
/// участника, зажать аватар — убрать его из чата.
struct RoleChatMembersRail: View {
    let members: [RoleChatMember]
    let addable: [RoleProfile]
    let canManage: Bool
    @Binding var isOpen: Bool
    let onMention: (RoleChatMember) -> Void
    let onAdd: (String) -> Void
    let onRemove: (RoleChatMember) -> Void

    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let avatar: TFAvatar.Size = .xl
    /// Аватар и по `TFSpacing.sm` с боков — «на размер иконки», не больше.
    static let openWidth: CGFloat = avatar.rawValue + TFSpacing.sm * 2
    static let restingWidth = TaskFamilyEdgeTabs.restingWidth

    private var width: CGFloat {
        let base = isOpen ? Self.openWidth : Self.restingWidth
        return min(Self.openWidth, max(Self.restingWidth, base - drag))
    }
    private var reveal: CGFloat {
        (width - Self.restingWidth) / (Self.openWidth - Self.restingWidth)
    }

    var body: some View {
        TaskFamilyEdgeTabs.tabShape
            .fill(TaskFamilyEdgeTabs.fillColor)
            .overlay {
                TaskFamilyTabOutline(openEdge: .trailing)
                    .stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth)
            }
            .compositingGroup()
            .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
            .overlay(alignment: .leading) {
                RoleChatMembersColumn(members: members, addable: addable, canManage: canManage,
                                      onMention: onMention, onAdd: onAdd, onRemove: onRemove)
                    .frame(width: Self.openWidth)
                    .opacity(reveal)
                    .allowsHitTesting(isOpen && drag == 0)
            }
            .clipShape(Rectangle().inset(by: -TaskFamilyEdgeTabs.shadowRadius * 2))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            // Полоса для пальца шире видимого края, чтобы край ловился.
            .padding(.leading, isOpen ? 0 : TaskFamilyEdgeZone.width - Self.restingWidth)
            .contentShape(Rectangle())
            .onTapGesture { if !isOpen { setOpen(true) } }
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let base = isOpen ? Self.openWidth : Self.restingWidth
                    let end = base - value.predictedEndTranslation.width
                    setOpen(end > (Self.openWidth + Self.restingWidth) / 2)
                })
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05), value: isOpen)
            .sensoryFeedback(.impact(weight: .light), trigger: isOpen)
            .accessibilityElement(children: isOpen ? .contain : .ignore)
            .accessibilityLabel(isOpen ? "Участники чата" : "Показать участников")
            .accessibilityAddTraits(isOpen ? [] : .isButton)
            .accessibilityAction { setOpen(!isOpen) }
            .accessibilityIdentifier("chat.membersRail")
    }

    private func setOpen(_ open: Bool) { isOpen = open }
}

/// Содержимое столбца: участники сверху вниз и «+» последним.
private struct RoleChatMembersColumn: View {
    let members: [RoleChatMember]
    let addable: [RoleProfile]
    let canManage: Bool
    let onMention: (RoleChatMember) -> Void
    let onAdd: (String) -> Void
    let onRemove: (RoleChatMember) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TFSpacing.md) {
                ForEach(members) { member in
                    Button { onMention(member) } label: {
                        RoleMemberAvatar(member: member, size: RoleChatMembersRail.avatar)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if canManage {
                            Button(role: .destructive) { onRemove(member) } label: {
                                Label("Убрать из чата", systemImage: "person.badge.minus")
                            }
                        }
                    }
                    .accessibilityLabel("Написать: \(member.name)")
                    .accessibilityIdentifier("chat.membersRail.\(member.id)")
                }
                if canManage { addButton }
            }
            .padding(.vertical, TFSpacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    private var addButton: some View {
        Menu {
            if addable.isEmpty {
                Text("Все роли уже в чате")
            } else {
                ForEach(addable) { profile in
                    Button(profile.title) { if let account = profile.accountID { onAdd(account) } }
                }
            }
        } label: {
            Image(systemName: "plus")
                .tfText(.title)
                .foregroundStyle(Color.tfSub)
                .frame(width: RoleChatMembersRail.avatar.rawValue, height: RoleChatMembersRail.avatar.rawValue)
                .overlay { Circle().strokeBorder(Color.tfSub, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
        }
        .accessibilityLabel("Добавить участника")
        .accessibilityIdentifier("chat.membersRail.add")
    }
}
