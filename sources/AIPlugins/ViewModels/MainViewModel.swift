import Combine
import Foundation

@MainActor
class MainViewModel: ObservableObject {
    @Published var plugins: [Plugin] = []
    @Published var selectedPlugin: Plugin?
    @Published var searchText: String = ""
    @Published var openTabs: [TabItem] = []
    @Published var activeTabId: UUID?

    private let pluginManager = PluginManager()
    private var allPlugins: [Plugin] = []
    let settingsViewModel: SettingsViewModel

    // 插件热重载相关
    private var pluginWatchTimer: Timer?
    private var lastPluginHash: String = ""
    private let watchInterval: TimeInterval = 3.0  // 每3秒检查一次

    init(settings: AppSettings) {
        self.settingsViewModel = SettingsViewModel(settings: settings)
    }

    var activeTab: TabItem? {
        openTabs.first { $0.id == activeTabId }
    }

    // Computed property for filtered and sorted plugins
    var filteredPlugins: [Plugin] {
        let filtered: [Plugin]

        if searchText.isEmpty {
            filtered = allPlugins
        } else {
            filtered = allPlugins.filter { plugin in
                plugin.name.localizedCaseInsensitiveContains(searchText)
                    || plugin.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort alphabetically by name
        return filtered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func loadPlugins() {
        // 使用正确的插件目录路径
        // DynamicPluginManager 会自动从以下位置加载:
        // 1. ~/Library/Application Support/ai_plugins/plugins (用户插件)
        // 2. Resources/plugins 或 Resources/AIPlugins/plugins (系统内置插件)

        let fileManager = FileManager.default

        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)

            // 尝试多个可能的插件路径
            var pluginDirectory: URL?

            // 首先尝试 AIPlugins/plugins（开发时）
            let devPath = resourceURL.appendingPathComponent("AIPlugins/plugins")
            if fileManager.fileExists(atPath: devPath.path) {
                pluginDirectory = devPath
                print("MainViewModel: Found plugins in development path: \(devPath.path)")
            } else {
                // 回退到 plugins（编译后）
                let buildPath = resourceURL.appendingPathComponent("plugins")
                if fileManager.fileExists(atPath: buildPath.path) {
                    pluginDirectory = buildPath
                    print("MainViewModel: Found plugins in build path: \(buildPath.path)")
                }
            }

            if let pluginDirectory = pluginDirectory {
                // 使用 PluginManager 的 discoverAllPlugins 方法
                // 这会同时加载动态插件（新格式）和旧版插件（单文件.js）
                allPlugins = pluginManager.discoverAllPlugins(in: pluginDirectory)
                plugins = filteredPlugins

                print("MainViewModel: Loaded \(allPlugins.count) total plugins")

                if allPlugins.isEmpty {
                    print("MainViewModel: Warning - No plugins found!")
                }

                // 启动插件监听
                startPluginWatcher()
            } else {
                print("MainViewModel: Error - No plugin directory found in Resources")
            }
        } else {
            print("MainViewModel: Error - Could not find resource path")
        }
    }

    // MARK: - 插件热重载

    /// 启动插件目录监听
    func startPluginWatcher() {
        // 记录初始哈希
        lastPluginHash = DynamicPluginManager.shared.getPluginDirectoryHash()

        // 停止之前的定时器（如果有）
        pluginWatchTimer?.invalidate()

        // 创建新的定时器
        pluginWatchTimer = Timer.scheduledTimer(withTimeInterval: watchInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.checkPluginChanges()
            }
        }

        print("MainViewModel: Plugin watcher started (checking every \(watchInterval) seconds)")
    }

    /// 停止插件目录监听
    func stopPluginWatcher() {
        pluginWatchTimer?.invalidate()
        pluginWatchTimer = nil
        print("MainViewModel: Plugin watcher stopped")
    }

    /// 检查插件是否有变化
    private func checkPluginChanges() async {
        let currentHash = DynamicPluginManager.shared.getPluginDirectoryHash()

        if currentHash != lastPluginHash {
            print("MainViewModel: Plugin directory changed, reloading plugins...")
            lastPluginHash = currentHash

            // 重新加载插件
            await reloadPlugins()
        }
    }

    /// 重新加载所有插件
    func reloadPlugins() async {
        let fileManager = FileManager.default

        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)

            // 尝试多个可能的插件路径
            var pluginDirectory: URL?

            // 首先尝试 AIPlugins/plugins（开发时）
            let devPath = resourceURL.appendingPathComponent("AIPlugins/plugins")
            if fileManager.fileExists(atPath: devPath.path) {
                pluginDirectory = devPath
            } else {
                // 回退到 plugins（编译后）
                let buildPath = resourceURL.appendingPathComponent("plugins")
                if fileManager.fileExists(atPath: buildPath.path) {
                    pluginDirectory = buildPath
                }
            }

            if let pluginDirectory = pluginDirectory {
                // 重新加载插件
                allPlugins = pluginManager.discoverAllPlugins(in: pluginDirectory)
                plugins = filteredPlugins

                print("MainViewModel: Reloaded \(allPlugins.count) total plugins")

                // 通知UI更新
                objectWillChange.send()
            }
        }
    }

    deinit {
        Task { @MainActor in
            self.stopPluginWatcher()
        }
    }

    func updateFilteredPlugins() {
        plugins = filteredPlugins
    }

    /// Opens a new tab for the given plugin
    func openTab(for plugin: Plugin) {
        print("--- MainViewModel: openTab called for plugin: \(plugin.name) ---")
        print(
            "Before change: openTabs count = \(openTabs.count), activeTabId = \(activeTabId?.uuidString ?? "nil")"
        )

        // Check if tab already exists
        if let existingTab = openTabs.first(where: { $0.plugin.id == plugin.id }) {
            print("Tab already exists. Setting active.")
            activeTabId = existingTab.id
        } else {
            // Create new tab with its own ViewModel
            let newTab = TabItem(plugin: plugin, settings: settingsViewModel.settings)
            print("Creating new tab with id: \(newTab.id.uuidString)")
            openTabs.append(newTab)
            activeTabId = newTab.id
        }

        // Update window title
        WindowTitleManager.shared.setPluginTitle(plugin.name)
        print(
            "After change: openTabs count = \(openTabs.count), activeTabId = \(activeTabId?.uuidString ?? "nil")"
        )
        print("----------------------------------------------------")
    }

    /// 打开带会话的新标签
    func openPluginInNewTab(
        _ plugin: Plugin, session: ConversationSession, historyManager: HistoryManager
    ) {
        // 创建新标签
        let newTab = TabItem(plugin: plugin, settings: settingsViewModel.settings)
        openTabs.append(newTab)
        activeTabId = newTab.id
        selectedPlugin = plugin

        // 加载会话到 ViewModel
        newTab.viewModel.loadSession(session, plugin: plugin, historyManager: historyManager)

        WindowTitleManager.shared.setPluginTitle(plugin.name)
        print("MainViewModel: Opened plugin '\(plugin.name)' with session '\(session.title)'")
    }

    /// Closes the tab with the given ID
    func closeTab(_ tabId: UUID, historyManager: HistoryManager? = nil) {
        print("--- MainViewModel: closeTab called for tabId: \(tabId.uuidString) ---")
        print(
            "Before close: openTabs count = \(openTabs.count), activeTabId = \(activeTabId?.uuidString ?? "nil")"
        )

        guard let index = openTabs.firstIndex(where: { $0.id == tabId }) else {
            print("MainViewModel: Tab not found with id: \(tabId.uuidString)")
            print("----------------------------------------------------")
            return
        }

        print("Closing tab at index \(index), plugin: \(openTabs[index].plugin.name)")

        // 保存会话（如果有交互内容）- 保持 tab 引用直到保存完成
        let tab = openTabs[index]

        if let historyManager = historyManager {
            // 先保存，保存完成后再删除标签页
            tab.viewModel.saveCurrentSession(historyManager: historyManager) { [weak self] saved in
                guard let self = self else { return }

                if saved {
                    print("MainViewModel: Session saved for tab: \(tab.plugin.name)")
                }

                // 保存完成后，执行实际的关闭逻辑
                self.performCloseTab(tabId)
            }
        } else {
            // 没有 historyManager，直接关闭
            performCloseTab(tabId)
        }
    }

    /// 实际执行关闭标签页的逻辑
    private func performCloseTab(_ tabId: UUID) {
        guard let index = openTabs.firstIndex(where: { $0.id == tabId }) else {
            print("MainViewModel: Tab not found during performCloseTab")
            return
        }

        openTabs.remove(at: index)
        print("Remaining tabs count: \(openTabs.count)")

        // Update active tab if the closed tab was active
        if activeTabId == tabId {
            print("Closed tab was active, updating active tab")
            if let newActiveTab = openTabs.last {
                activeTabId = newActiveTab.id
                selectedPlugin = newActiveTab.plugin
                WindowTitleManager.shared.setPluginTitle(newActiveTab.plugin.name)
                print("New active tab: \(newActiveTab.plugin.name) (\(newActiveTab.id.uuidString))")
            } else {
                print("No tabs remaining, clearing selection")
                activeTabId = nil
                selectedPlugin = nil
                WindowTitleManager.shared.setTitle(section: "plugins")
            }
        } else {
            print(
                "Closed tab was not active, keeping current active tab: \(activeTabId?.uuidString ?? "nil")"
            )
        }
        print(
            "After close: openTabs count = \(openTabs.count), activeTabId = \(activeTabId?.uuidString ?? "nil")"
        )
        print("----------------------------------------------------")
    }
}
