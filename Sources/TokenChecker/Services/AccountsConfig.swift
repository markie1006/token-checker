import Foundation

/// `~/.config/token-checker/accounts.json` から複数 Codex アカウントを読み込む。
///
/// ファイルが存在しない・パースできない場合はデフォルトの 1 アカウント構成にフォールバック。
///
/// accounts.json の例:
/// ```json
/// {
///   "codexAccounts": [
///     { "label": "Work",     "home": "/Users/you/.codex-work" },
///     { "label": "Personal", "home": null }
///   ]
/// }
/// ```
/// `home` を省略または null にすると `~/.codex`（Codex のデフォルト）を使用する。
struct AccountsConfig: Decodable, Sendable {
    let codexAccounts: [CodexAccountEntry]

    struct CodexAccountEntry: Decodable, Sendable {
        let label: String
        let home: String?
    }

    static func load() -> AccountsConfig {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/token-checker/accounts.json")
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AccountsConfig.self, from: data),
           !config.codexAccounts.isEmpty
        {
            return config.expandingTilde()
        }
        return AccountsConfig(codexAccounts: [CodexAccountEntry(label: "Codex", home: nil)])
    }

    /// `home` に含まれる先頭の `~` をホームディレクトリのフルパスに展開して返す。
    private func expandingTilde() -> AccountsConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = codexAccounts.map { entry in
            let expandedHome = entry.home.map { path in
                path.hasPrefix("~/") ? home + path.dropFirst(1) : path
            }
            return CodexAccountEntry(label: entry.label, home: expandedHome)
        }
        return AccountsConfig(codexAccounts: expanded)
    }
}
