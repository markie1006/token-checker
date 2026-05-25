import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class UsageViewModel {
    // applicationWillTerminate から MainActor を経由せず shutdown を呼べるよう
    // nonisolated 化する。providers 自体は immutable なので Sendable 違反は起きない。
    private nonisolated let claudeProvider: UsageProvider
    private nonisolated let codexEntries: [CodexEntry]

    var snapshot: UsageSnapshot = .empty
    var isLoading: Bool = false
    var pollingInterval: PollingInterval {
        didSet { persistInterval() }
    }

    /// 複数 Codex アカウントを保持する内部型。
    private nonisolated struct CodexEntry: Sendable {
        let label: String
        let home: String?
        let provider: UsageProvider
    }

    init(
        claudeProvider: UsageProvider = ClaudeUsageProvider(),
        codexEntries: [(label: String, home: String?, provider: UsageProvider)]? = nil
    ) {
        self.claudeProvider = claudeProvider
        if let overrides = codexEntries {
            self.codexEntries = overrides.map { CodexEntry(label: $0.label, home: $0.home, provider: $0.provider) }
        } else {
            let config = AccountsConfig.load()
            self.codexEntries = config.codexAccounts.map { account in
                CodexEntry(
                    label: account.label,
                    home: account.home,
                    provider: CodexUsageProvider(label: account.label, home: account.home)
                )
            }
        }
        self.pollingInterval = Self.loadPersistedInterval()
    }

    /// `task(id: pollingInterval)` から駆動するメインループ。
    func runPollingLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval.seconds * 1_000_000_000))
            } catch {
                return
            }
            await refresh()
        }
    }

    /// アプリ終了時に子プロセスや永続接続を解放するためのクロージャを返す。
    nonisolated func makeShutdownHandler() -> @Sendable () async -> Void {
        let claude = claudeProvider
        let entries = codexEntries
        return {
            await claude.shutdown()
            for entry in entries { await entry.provider.shutdown() }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let claude = fetchClaude()
        let codexResults = await fetchAllCodex()

        let c = await claude
        snapshot = UsageSnapshot(claude: c, codexAccounts: codexResults, fetchedAt: Date())
    }

    private func fetchClaude() async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await claudeProvider.fetch())
        } catch let err as DomainError {
            Logger.claude.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// 全 Codex アカウントを並列取得し、設定ファイルの順序で返す。
    private func fetchAllCodex() async -> [CodexAccountSnapshot] {
        let entries = codexEntries
        return await withTaskGroup(of: (Int, CodexAccountSnapshot).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    do {
                        let usage = try await entry.provider.fetch()
                        return (index, CodexAccountSnapshot(label: entry.label, home: entry.home, result: .success(usage)))
                    } catch let err as DomainError {
                        Logger.codex.error("fetch failed [\(entry.label)]: \(err.localizedDescription)")
                        return (index, CodexAccountSnapshot(label: entry.label, home: entry.home, result: .failure(err)))
                    } catch {
                        return (index, CodexAccountSnapshot(label: entry.label, home: entry.home, result: .failure(.network(error.localizedDescription))))
                    }
                }
            }
            var results: [(Int, CodexAccountSnapshot)] = []
            for await r in group { results.append(r) }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }
    }

    // MARK: - ログインボタン

    func openClaudeLogin() {
        spawnTerminalCommand("claude login")
    }

    /// Codex ログイン。`home` が指定されている場合は CODEX_HOME を前置する。
    func openCodexLogin(home: String?) {
        // CODEX_HOME のパスはユーザー自身の設定ファイル由来だが、
        // AppleScript の文字列インジェクションを防ぐため英数字・パス文字のみ許可する。
        if let home = home {
            let allowedChars = CharacterSet.alphanumerics.union(.init(charactersIn: "/_\\-.~"))
            guard home.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
                Logger.ui.error("codex login: unsafe CODEX_HOME path rejected: \(home)")
                return
            }
            spawnTerminalCommand("CODEX_HOME=\(home) codex login")
        } else {
            spawnTerminalCommand("codex login")
        }
    }

    private func spawnTerminalCommand(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do { try process.run() } catch {
            Logger.ui.error("login spawn failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 永続化

    private static let intervalKey = "pollingInterval"

    private static func loadPersistedInterval() -> PollingInterval {
        let raw = UserDefaults.standard.integer(forKey: intervalKey)
        return PollingInterval(rawValue: raw) ?? .default
    }

    private func persistInterval() {
        UserDefaults.standard.set(pollingInterval.rawValue, forKey: Self.intervalKey)
    }
}
