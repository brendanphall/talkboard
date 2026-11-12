import Testing
@testable import TalkboardCore

struct LearningContentTests {
    @Test func alphabetHasOrderedLettersAndExplicitLetterNames() {
        #expect(LearningContent.letters.map(\.label) == Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        #expect(LearningContent.letters.map(\.spokenText) == ["ay", "bee", "see", "dee", "ee", "eff", "gee", "aitch", "eye", "jay", "kay", "ell", "em", "en", "oh", "pee", "cue", "ar", "ess", "tee", "you", "vee", "double you", "ex", "why", "zee"])
        #expect(Set(LearningContent.letters.map(\.id)).count == 26)
    }
    @Test func numbersHaveExactOrderedMeaningsThroughTwenty() {
        #expect(LearningContent.numbers.map(\.label) == (1...20).map(String.init))
        #expect(LearningContent.numbers.map(\.spokenText) == ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"])
        #expect(Set(LearningContent.numbers.map(\.id)).count == 20)
    }
}
