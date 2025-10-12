/**
 * Bridge Handlers
 * 各个功能模块的 Bridge 处理器实现
 */

import Foundation
import AppKit

// MARK: - AI Bridge Handler

@MainActor
class AIBridgeHandler: BridgeHandler {
    var methodPrefix: String { "ai." }

    private let aiService = AIAPIService.shared
    private let settings = AppSettings.shared

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "ai.chat":
            return await handleChat(params)
        case "ai.streamChat":
            return await handleStreamChat(params)
        case "ai.listModels":
            return await handleListModels()
        case "ai.getCurrentModel":
            return await handleGetCurrentModel()
        default:
            return .failure("Unknown AI method: \(method)")
        }
    }

    private func handleChat(_ params: [String: Any]) async -> BridgeResult {
        guard let prompt = params["prompt"] as? String else {
            return .failure("Missing prompt parameter")
        }

        let systemPrompt = params["systemPrompt"] as? String
        let temperature = params["temperature"] as? Double
        let maxTokens = params["maxTokens"] as? Int
        let model = params["model"] as? String

        do {
            // 构建消息
            var messages: [[String: String]] = []
            if let systemPrompt = systemPrompt {
                messages.append(["role": "system", "content": systemPrompt])
            }
            messages.append(["role": "user", "content": prompt])

            // 调用 AI API（这里需要根据实际的 AIAPIService 实现调整）
            let response = try await aiService.sendChatRequest(messages: messages)

            return .success([
                "content": response.content,
                "model": response.model,
                "usage": [
                    "promptTokens": response.promptTokens,
                    "completionTokens": response.completionTokens,
                    "totalTokens": response.totalTokens
                ]
            ])
        } catch {
            return .failure("AI chat failed: \(error.localizedDescription)")
        }
    }

    private func handleStreamChat(_ params: [String: Any]) async -> BridgeResult {
        guard let streamId = params["streamId"] as? String,
              let prompt = params["prompt"] as? String else {
            return .failure("Missing required parameters")
        }

        let systemPrompt = params["systemPrompt"] as? String

        // 构建消息
        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        // 启动流式请求（异步，不等待完成）
        Task {
            do {
                try await aiService.streamChatRequest(messages: messages) { chunk in
                    // 通过 Bridge 发送 chunk
                    // 这里需要访问 SquirrelBridge 实例
                    NotificationCenter.default.post(
                        name: .bridgeStreamChunk,
                        object: nil,
                        userInfo: ["streamId": streamId, "chunk": chunk]
                    )
                }

                // 完成
                NotificationCenter.default.post(
                    name: .bridgeStreamComplete,
                    object: nil,
                    userInfo: ["streamId": streamId]
                )
            } catch {
                // 错误
                NotificationCenter.default.post(
                    name: .bridgeStreamError,
                    object: nil,
                    userInfo: ["streamId": streamId, "error": error.localizedDescription]
                )
            }
        }

        return .success(nil)
    }

    private func handleListModels() async -> BridgeResult {
        let models = settings.availableModels.map { model in
            [
                "id": model.id,
                "name": model.name,
                "provider": model.provider,
                "contextWindow": model.contextWindow
            ] as [String: Any]
        }
        return .success(models)
    }

    private func handleGetCurrentModel() async -> BridgeResult {
        guard let currentModel = settings.availableModels.first(where: { $0.id == settings.selectedModelId }) else {
            return .failure("No model selected")
        }

        return .success([
            "id": currentModel.id,
            "name": currentModel.name,
            "provider": currentModel.provider,
            "contextWindow": currentModel.contextWindow
        ])
    }
}

// MARK: - RAG Bridge Handler

@MainActor
class RAGBridgeHandler: BridgeHandler {
    var methodPrefix: String { "rag." }

    private let ragService = RAGService.shared

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "rag.query":
            return await handleQuery(params)
        case "rag.listKnowledgeBases":
            return await handleListKnowledgeBases()
        case "rag.embed":
            return await handleEmbed(params)
        default:
            return .failure("Unknown RAG method: \(method)")
        }
    }

    private func handleQuery(_ params: [String: Any]) async -> BridgeResult {
        guard let text = params["text"] as? String,
              let kbName = params["knowledgeBase"] as? String else {
            return .failure("Missing required parameters")
        }

        // 查找知识库
        guard let kb = await ragService.getKnowledgeBases().first(where: { $0.name == kbName }) else {
            return .failure("Knowledge base not found: \(kbName)")
        }

        let topK = params["topK"] as? Int ?? 5
        let minSimilarity = params["minSimilarity"] as? Double ?? 0.7

        do {
            let result = try await ragService.enhancePrompt(text, using: kb)

            return .success([
                "chunks": result.retrievedChunks.map { chunk in
                    [
                        "content": chunk.content,
                        "similarity": chunk.similarity,
                        "source": chunk.source,
                        "metadata": chunk.metadata as Any
                    ]
                },
                "enhancedPrompt": result.enhancedPrompt,
                "averageSimilarity": result.averageSimilarity
            ])
        } catch {
            return .failure("RAG query failed: \(error.localizedDescription)")
        }
    }

    private func handleListKnowledgeBases() async -> BridgeResult {
        let kbs = await ragService.getKnowledgeBases().map { kb in
            [
                "id": kb.id.uuidString,
                "name": kb.name,
                "description": kb.description,
                "documentCount": kb.documentCount,
                "createdAt": ISO8601DateFormatter().string(from: kb.createdAt)
            ] as [String: Any]
        }
        return .success(kbs)
    }

    private func handleEmbed(_ params: [String: Any]) async -> BridgeResult {
        guard let text = params["text"] as? String else {
            return .failure("Missing text parameter")
        }

        do {
            let embedding = try await ragService.embed(text: text)
            return .success(embedding)
        } catch {
            return .failure("Embedding failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - File Bridge Handler

@MainActor
class FileBridgeHandler: BridgeHandler {
    var methodPrefix: String { "file." }

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "file.read":
            return await handleRead(params)
        case "file.write":
            return await handleWrite(params)
        case "file.select":
            return await handleSelect(params)
        case "file.getInfo":
            return await handleGetInfo(params)
        default:
            return .failure("Unknown file method: \(method)")
        }
    }

    private func handleRead(_ params: [String: Any]) async -> BridgeResult {
        guard let path = params["path"] as? String else {
            return .failure("Missing path parameter")
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return .success(content)
        } catch {
            return .failure("File read failed: \(error.localizedDescription)")
        }
    }

    private func handleWrite(_ params: [String: Any]) async -> BridgeResult {
        guard let path = params["path"] as? String,
              let content = params["content"] as? String else {
            return .failure("Missing required parameters")
        }

        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success(nil)
        } catch {
            return .failure("File write failed: \(error.localizedDescription)")
        }
    }

    private func handleSelect(_ params: [String: Any]) async -> BridgeResult {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = params["allowMultiple"] as? Bool ?? false

        if let allowedTypes = params["allowedTypes"] as? [String], !allowedTypes.isEmpty {
            openPanel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        }

        if let message = params["message"] as? String {
            openPanel.message = message
        }

        let response = openPanel.runModal()
        if response == .OK {
            let urls = openPanel.urls.map { $0.path }
            return .success(urls)
        } else {
            return .success([])
        }
    }

    private func handleGetInfo(_ params: [String: Any]) async -> BridgeResult {
        guard let path = params["path"] as? String else {
            return .failure("Missing path parameter")
        }

        let url = URL(fileURLWithPath: path)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let size = attributes[.size] as? Int ?? 0

            return .success([
                "path": path,
                "name": url.lastPathComponent,
                "size": size,
                "extension": url.pathExtension
            ])
        } catch {
            return .failure("Get file info failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Storage Bridge Handler

@MainActor
class StorageBridgeHandler: BridgeHandler {
    var methodPrefix: String { "storage." }

    private let defaults = UserDefaults.standard
    private let storagePrefix = "plugin_storage_"

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "storage.get":
            return handleGet(params)
        case "storage.set":
            return handleSet(params)
        case "storage.remove":
            return handleRemove(params)
        case "storage.clear":
            return handleClear()
        case "storage.keys":
            return handleKeys()
        default:
            return .failure("Unknown storage method: \(method)")
        }
    }

    private func handleGet(_ params: [String: Any]) -> BridgeResult {
        guard let key = params["key"] as? String else {
            return .failure("Missing key parameter")
        }

        let fullKey = storagePrefix + key
        let value = defaults.object(forKey: fullKey)
        return .success(value)
    }

    private func handleSet(_ params: [String: Any]) -> BridgeResult {
        guard let key = params["key"] as? String else {
            return .failure("Missing key parameter")
        }

        let value = params["value"]
        let fullKey = storagePrefix + key
        defaults.set(value, forKey: fullKey)
        return .success(nil)
    }

    private func handleRemove(_ params: [String: Any]) -> BridgeResult {
        guard let key = params["key"] as? String else {
            return .failure("Missing key parameter")
        }

        let fullKey = storagePrefix + key
        defaults.removeObject(forKey: fullKey)
        return .success(nil)
    }

    private func handleClear() -> BridgeResult {
        let allKeys = defaults.dictionaryRepresentation().keys
        let pluginKeys = allKeys.filter { $0.hasPrefix(storagePrefix) }
        pluginKeys.forEach { defaults.removeObject(forKey: $0) }
        return .success(nil)
    }

    private func handleKeys() -> BridgeResult {
        let allKeys = defaults.dictionaryRepresentation().keys
        let pluginKeys = allKeys
            .filter { $0.hasPrefix(storagePrefix) }
            .map { String($0.dropFirst(storagePrefix.count)) }
        return .success(Array(pluginKeys))
    }
}

// MARK: - System Bridge Handler

@MainActor
class SystemBridgeHandler: BridgeHandler {
    var methodPrefix: String { "system." }

    private let settings = AppSettings.shared

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "system.notify":
            return handleNotify(params)
        case "system.openURL":
            return handleOpenURL(params)
        case "system.copyToClipboard":
            return handleCopyToClipboard(params)
        case "system.getClipboard":
            return handleGetClipboard()
        case "system.getSettings":
            return handleGetSettings()
        default:
            return .failure("Unknown system method: \(method)")
        }
    }

    private func handleNotify(_ params: [String: Any]) -> BridgeResult {
        guard let title = params["title"] as? String,
              let message = params["message"] as? String else {
            return .failure("Missing required parameters")
        }

        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = (params["sound"] as? Bool ?? true) ? NSUserNotificationDefaultSoundName : nil

        NSUserNotificationCenter.default.deliver(notification)
        return .success(nil)
    }

    private func handleOpenURL(_ params: [String: Any]) -> BridgeResult {
        guard let urlString = params["url"] as? String,
              let url = URL(string: urlString) else {
            return .failure("Invalid URL")
        }

        NSWorkspace.shared.open(url)
        return .success(nil)
    }

    private func handleCopyToClipboard(_ params: [String: Any]) -> BridgeResult {
        guard let text = params["text"] as? String else {
            return .failure("Missing text parameter")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .success(nil)
    }

    private func handleGetClipboard() -> BridgeResult {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        return .success(text)
    }

    private func handleGetSettings() -> BridgeResult {
        let settingsDict: [String: Any] = [
            "userName": settings.userName,
            "userAvatarPath": settings.userAvatarPath,
            "selectedModelId": settings.selectedModelId
        ]
        return .success(settingsDict)
    }
}

// MARK: - Log Bridge Handler

@MainActor
class LogBridgeHandler: BridgeHandler {
    var methodPrefix: String { "log." }

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        let message = params["message"] as? String ?? ""
        let args = params["args"] as? [Any] ?? []

        let fullMessage = ([message] + args.map { String(describing: $0) }).joined(separator: " ")

        switch method {
        case "log.debug":
            print("[Plugin Debug] \(fullMessage)")
        case "log.info":
            print("[Plugin Info] \(fullMessage)")
        case "log.warn":
            print("[Plugin Warn] \(fullMessage)")
        case "log.error":
            print("[Plugin Error] \(fullMessage)")
        default:
            print("[Plugin] \(fullMessage)")
        }

        return .success(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let bridgeStreamChunk = Notification.Name("BridgeStreamChunk")
    static let bridgeStreamComplete = Notification.Name("BridgeStreamComplete")
    static let bridgeStreamError = Notification.Name("BridgeStreamError")
}

// MARK: - UTType Extension

import UniformTypeIdentifiers

extension UTType {
    init?(filenameExtension: String) {
        self.init(filenameExtension: filenameExtension)
    }
}
