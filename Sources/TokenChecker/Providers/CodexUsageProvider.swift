import Foundation

/// `codex app-server` を介して Codex の rate limit を取得。
/// アプリのライフタイム中 1 プロセスを共有する。失敗時は再起動を試みる。
final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    let label: String
    let home: String?
    private let client: CodexAppServerClient

    /// - Parameters:
    ///   - label: UI に表示するアカウント名（例: "Work", "Personal"）
    ///   - home:  `CODEX_HOME` として渡すディレクトリ。nil のときはデフォルト (`~/.codex`) を使用
    init(label: String = "Codex", home: String? = nil) {
        self.label = label
        self.home = home
        self.client = CodexAppServerClient(codexHome: home)
    }

    func fetch() async throws -> ServiceUsage {
        do {
            try await client.start()
            let dto = try await client.readRateLimits()
            return ServiceUsage(
                fiveHour: dto.fiveHourRateLimit(),
                weekly: dto.weeklyRateLimit(),
                weeklySonnet: nil
            )
        } catch DomainError.codexProcessExited {
            // 一度落ちていたら再起動して再試行
            await client.stop()
            try await client.start()
            let dto = try await client.readRateLimits()
            return ServiceUsage(
                fiveHour: dto.fiveHourRateLimit(),
                weekly: dto.weeklyRateLimit(),
                weeklySonnet: nil
            )
        }
    }

    func shutdown() async {
        await client.stop()
    }
}
