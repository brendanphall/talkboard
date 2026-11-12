import SwiftUI
import TalkboardCore

/// A separate, optional activity. Communication remains one Home tap away.
struct LearningView: View {
    let speech: AppleSpeechService
    @State private var numbers = false
    @State private var selected: ConceptID?

    private var content: [Concept] { numbers ? LearningContent.numbers : LearningContent.letters }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                modeButton("ABC", numbers: false, identifier: "learning-letters")
                modeButton("123", numbers: true, identifier: "learning-numbers")
            }
            .padding(.top, 12)
            GeometryReader { geometry in
                let columns = numbers ? 5 : 7
                let rows = 4
                let gap: CGFloat = 12
                let height = max(44, (geometry.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                    ForEach(Array(content.enumerated()), id: \.element.id) { index, concept in
                        Button {
                            selected = concept.id
                            speech.controller.speak(concept)
                        } label: {
                            VStack(spacing: 6) {
                                Text(concept.label)
                                    .font(.system(size: numbers ? 36 : 48, weight: .semibold, design: .rounded))
                                    .minimumScaleFactor(0.6)
                                if numbers { QuantityDots(count: index + 1) }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(selected == concept.id ? Color.green : Color.secondary.opacity(0.2),
                                                  lineWidth: selected == concept.id ? 4 : 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(numbers ? concept.spokenText : "Letter \(concept.label)")
                        .accessibilityIdentifier("\(numbers ? "number" : "letter")-\(concept.label)")
                        .accessibilityAddTraits(selected == concept.id ? [.isSelected] : [])
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemGroupedBackground))
        .onDisappear { speech.controller.stop() }
    }

    private func modeButton(_ title: String, numbers value: Bool, identifier: String) -> some View {
        Button {
            speech.controller.stop()
            selected = nil
            numbers = value
        } label: {
            Text(title)
                .font(.title.bold())
                .frame(width: 140, height: 56)
                .foregroundStyle(numbers == value ? .white : Color.primary)
                .background(numbers == value ? Color(red: 0.10, green: 0.43, blue: 0.22) : Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value ? "Numbers" : "Alphabet")
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(numbers == value ? [.isSelected] : [])
    }
}

private struct QuantityDots: View {
    let count: Int
    var body: some View {
        // Four rows of five make quantities comparable without changing tile size.
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { column in
                        Circle().fill(Color(red: 0.10, green: 0.43, blue: 0.22))
                            .frame(width: 8, height: 8)
                            .opacity(row * 5 + column < count ? 1 : 0)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
