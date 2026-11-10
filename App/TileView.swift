import SwiftUI
import TalkboardCore

struct TileView: View {
    let concept: Concept
    var image: UIImage? = nil
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                (image.map { Image(uiImage: $0) } ?? Image(systemName: "photo"))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .accessibilityHidden(true)
                Text(concept.label)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color(uiColor: .systemGray4) : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Color.primary : Color(uiColor: .separator), lineWidth: selected ? 3 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(concept.label)
        .accessibilityIdentifier("tile-\(concept.id.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
