import XCTest

let expectedFailureDescriptionPrefix =
"Asynchronous wait failed: Exceeded timeout of 0 seconds, with unfulfilled expectations: \"testShouldNotFulfillExpectationWhenTimeoutExpires"

class XCTestCasePromiseKitSwiftTests: XCTestCase {
    override func recordFailureWithDescription(
        description: String,
        inFile filePath: String,
        atLine lineNumber: UInt,
        expected: Bool) {
            if (!description.hasPrefix(expectedFailureDescriptionPrefix)) {
                // recorded failure wasn't the expected timeout
                super.recordFailureWithDescription(
                    "expected test description starting with <\(expectedFailureDescriptionPrefix)> but was <\(description)>",
                    inFile: filePath,
                    atLine: lineNumber,
                    expected: expected)
            }
    }

    func testShouldNotFulfillExpectationWhenTimeoutExpires() {
        guard NSProcessInfo.processInfo().wmf_isOperatingSystemMajorVersionAtLeast(9) else {
            print("Skipping \(self.dynamicType).\(#function) since it crashes with symbolication errors on iOS < 9")
            return
        }

        var resolve: (() -> Void)!
        expectPromise(toResolve(), timeout: 0) { () -> Promise<Void> in
            let (p, fulfill, _) = Promise<Void>.pendingPromise()
            resolve = fulfill
            return p
        }
        // Resolve after wait context, which we should handle internally so it doesn't throw an assertion.
        resolve()
    }
}
