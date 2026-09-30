import Foundation

var failures = 0

func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name) (\(file):\(line))")
    }
}

func checkEqual<T: Equatable>(
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
