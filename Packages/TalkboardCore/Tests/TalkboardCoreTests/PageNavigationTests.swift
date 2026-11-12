import Testing
@testable import TalkboardCore

struct PageNavigationTests {
    @Test func boundariesNeverWrap() {
        var pages = PageNavigation(count: 3)
        pages.previous()
        #expect(pages.index == 0)
        #expect(!pages.canGoBack)
        pages.next()
        #expect(pages.index == 1)
        pages.next()
        pages.next()
        #expect(pages.index == 2)
        #expect(!pages.canGoForward)
        pages.previous()
        #expect(pages.index == 1)
        pages.home()
        #expect(pages.index == 0)
    }
    @Test func arbitraryPageCountsAndSinglePage() {
        for count in [1, 2, 7, 40] {
            var pages = PageNavigation(count: count)
            for _ in 0..<count + 3 { pages.next() }
            #expect(pages.index == count - 1)
            pages.home()
            #expect(pages.index == 0)
        }
        let single = PageNavigation(count: 1)
        #expect(!single.canGoBack && !single.canGoForward)
    }
}
