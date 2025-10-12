import AppKit
import SwiftUI

// MARK: - Modern Plugin Detail View with Native SwiftUI TabView

struct PluginDetailView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var historyManager: HistoryManager

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            ModernTabBar(
                tabs: viewModel.openTabs,
                activeTabId: $viewModel.activeTabId,
                onSelectTab: { tabId in
                    viewModel.activeTabId = tabId
                    if let tab = viewModel.openTabs.first(where: { $0.id == tabId }) {
                        viewModel.selectedPlugin = tab.plugin
                        WindowTitleManager.shared.setPluginTitle(tab.plugin.name)
                    }
                },
                onCloseTab: { tabId in
                    viewModel.closeTab(tabId, historyManager: historyManager)
                }
            )

            Divider()

            // Tab content - render ALL tabs to preserve state, but use proper WebView management
            ZStack {
                ForEach(viewModel.openTabs) { tab in
                    TabContentView(
                        tab: tab,
                        settings: viewModel.settingsViewModel.settings,
                        isActive: tab.id == viewModel.activeTabId
                    )
                    .opacity(tab.id == viewModel.activeTabId ? 1 : 0)
                    .zIndex(tab.id == viewModel.activeTabId ? 1 : 0)
                }
            }

            // Show placeholder if no tabs
            if viewModel.openTabs.isEmpty {
                // Placeholder when no tabs
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No plugin selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Modern Tab Bar

struct ModernTabBar: View {
    let tabs: [TabItem]
    @Binding var activeTabId: UUID?
    let onSelectTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    ModernTabButton(
                        tab: tab,
                        isActive: tab.id == activeTabId,
                        onSelect: {
                            onSelectTab(tab.id)
                        },
                        onClose: {
                            onCloseTab(tab.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 44)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Modern Tab Button

struct ModernTabButton: View {
    let tab: TabItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Text(getPluginIcon(for: tab.plugin.mode))
                .font(.system(size: 14))

            // Title
            Text(tab.plugin.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            // Close button
            Button(action: {
                print("ModernTabButton: Close button clicked for tab: \(tab.plugin.name)")
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(isHovering ? Color.secondary.opacity(0.2) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .foregroundColor(isActive ? .primary : .secondary)
        .contentShape(Rectangle())
        .onTapGesture {
            print("ModernTabButton: Tab tapped: \(tab.plugin.name)")
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func getPluginIcon(for mode: PluginMode) -> String {
        switch mode {
        case .chat:
            return "💬"
        case .bot:
            return "🤖"
        case .agent:
            return "🎯"
        case .role:
            return "🎭"
        case .unknown:
            return "❓"
        }
    }
}

// MARK: - Tab Content View

struct TabContentView: View {
    @ObservedObject var tab: TabItem
    let settings: AppSettings?
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            // WebView content area - takes all available space
            ZStack {
                PluginWebView(
                    viewModel: tab.viewModel,
                    tabId: tab.viewModel.tabId,
                    htmlContent: tab.viewModel.webViewContent,
                    settings: settings,
                    isActive: isActive
                )

                // Loading overlay
                if tab.viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle())

                        Text(tab.viewModel.loadingMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Input area - always at the bottom
            ExpandableTextInput(
                text: $tab.viewModel.inputPrompt,
                selectedKnowledgeBase: $tab.viewModel.selectedKnowledgeBase,
                placeholder: NSLocalizedString("enter_prompt", bundle: .aiPlugins, comment: ""),
                onSend: {
                    print("===== TabContentView: onSend triggered =====")
                    print("Tab ID: \(tab.id.uuidString.prefix(8))")
                    print("Plugin: \(tab.plugin.name)")
                    print("Input prompt: '\(tab.viewModel.inputPrompt)'")

                    // Capture the prompt BEFORE clearing
                    let currentPrompt = tab.viewModel.inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !currentPrompt.isEmpty {
                        print("Executing plugin with prompt: '\(currentPrompt)'")

                        // Set prompt BEFORE calling runPlugin
                        tab.viewModel.prompt = currentPrompt

                        // Clear input immediately with explicit UI update
                        DispatchQueue.main.async {
                            tab.viewModel.inputPrompt = ""
                            tab.viewModel.objectWillChange.send()
                            print("Input cleared and UI refreshed")
                        }

                        // Call runPlugin
                        tab.viewModel.runPlugin(
                            plugin: tab.plugin,
                            knowledgeBase: tab.viewModel.selectedKnowledgeBase
                        )
                        print("Plugin execution started")
                    } else {
                        print("WARNING: Input prompt is empty or whitespace only!")
                    }
                    print("==========================================")
                }
            )
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            print("TabContentView appeared for plugin: \(tab.plugin.name)")
            print("  Tab ID: \(tab.id.uuidString.prefix(8))")
            print("  WebView content length: \(tab.viewModel.webViewContent.count)")
        }
    }
}

