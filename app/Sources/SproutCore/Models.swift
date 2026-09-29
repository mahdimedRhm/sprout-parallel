import Foundation

/// Output of `sprout-parallel status --json`.
public struct Status: Codable, Equatable {
    public let projects: [Project]

    public static func decode(_ data: Data) throws -> Status {
        try JSONDecoder().decode(Status.self, from: data)
    }
}

public struct Project: Codable, Equatable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public let branches: [String]
    public let worktrees: [Worktree]

    public var id: String { name }
}

public struct Worktree: Codable, Equatable, Hashable, Identifiable {
    public let branch: String
    public let folder: String
    public let path: String
    public let base: String
    public let changes: Int
    public let ahead: Int?
    public let behind: Int?
    public let lastCommit: LastCommit?
    public let mysqlDb: String?
    public let redisDb: Int?
    public let redisPrefix: String?

    public var id: String { path }
    public var isDirty: Bool { changes > 0 }
}

public struct LastCommit: Codable, Equatable, Hashable {
    public let hash: String
    public let subject: String
    public let when: String
}
