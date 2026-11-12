import Foundation

/// Fixed activity content, separate from every saved communication board.
public enum LearningContent {
    public static let letters: [Concept] = {
        let labels = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        let names = ["ay", "bee", "see", "dee", "ee", "eff", "gee", "aitch", "eye", "jay", "kay", "ell", "em", "en", "oh", "pee", "cue", "ar", "ess", "tee", "you", "vee", "double you", "ex", "why", "zee"]
        return zip(labels, names).map { label, name in
            Concept(id: ConceptID(rawValue: "letter-\(label)"), label: label, spokenText: name)
        }
    }()

    public static let numbers: [Concept] = {
        let names = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        return names.enumerated().map { index, name in
            Concept(id: ConceptID(rawValue: "number-\(index + 1)"), label: String(index + 1), spokenText: name)
        }
    }()
}
