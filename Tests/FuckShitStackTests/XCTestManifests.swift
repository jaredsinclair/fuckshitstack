import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(FuckShitStackTests.allTests),
    ]
}
#endif
