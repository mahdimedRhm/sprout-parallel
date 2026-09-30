import Foundation

/// The commands behind the serve and queue services.
public enum ServiceCommand {
    public static let serve = "php artisan serve"

    /// Horizon when the worktree requires it, else a plain queue worker.
    public static func queue(worktreePath: String) -> String {
        let composer = URL(fileURLWithPath: worktreePath).appendingPathComponent("composer.json")
        let contents = (try? String(contentsOf: composer, encoding: .utf8)) ?? ""
        return contents.contains("\"laravel/horizon\"") ? "php artisan horizon" : "php artisan queue:work"
    }
}
