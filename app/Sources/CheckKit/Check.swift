import Foundation

/// Number of failed checks so far; `finishChecks()` exits non-zero if any.
public var failures = 0

public func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name) (\(file):\(line))")
    }
}

public func checkEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ name: String,
    file: StaticString = #fileID, line: UInt = #line
) {
    if actual == expected {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): expected \(expected), got \(actual) (\(file):\(line))")
    }
}

/// Prints the summary and exits: 0 when every check passed, 1 otherwise.
public func finishChecks() -> Never {
    print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
    exit(failures == 0 ? 0 : 1)
}
