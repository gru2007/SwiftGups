import SwiftUI

/// Баннер, объясняющий почему некоторые институты не доступны в списке выбора:
/// сервер ДВГУПС вернул `null` в поле id.
struct FacultyMissingIdBanner: View {
    let missingNames: [String]
    
    var body: some View {
        guard !missingNames.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Некоторые институты не отображаются")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text("Сайт ДВГУПС не назначил им ID, поэтому приложение не может загрузить по ним группы/расписание.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(missingNames.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
        )
    }
}

