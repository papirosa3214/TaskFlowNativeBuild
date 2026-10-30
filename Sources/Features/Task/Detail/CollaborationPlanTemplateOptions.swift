import SwiftUI

/// Общие пункты системного Menu «Предложить план по шаблону».
struct CollaborationPlanTemplateOptions: View {
    let select: (String) -> Void

    var body: some View {
        ForEach(CollaborationPlanTemplate.all, id: \.profile) { template in
            Button { select(template.profile) } label: {
                Label(template.title, systemImage: template.icon)
            }
        }
    }
}
