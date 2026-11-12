import SwiftUI

struct ArtworkCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    private var credits: String {
        guard let url = Bundle.main.url(forResource: "ALPHA-SYMBOL-CREDITS", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "See THIRD_PARTY_NOTICES.md in the Talkboard source for artwork credits and license terms."
        }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(credits)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityIdentifier("artwork-credits")
            }
            .navigationTitle("About Talkboard")
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("about-done") }
        }
    }
}
