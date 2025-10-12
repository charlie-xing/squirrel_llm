/**
 * Squirrel Bridge v2.0.0
 * 新一代插件架构 - Swift Bridge 核心通信层
 *
 * @description 提供 JavaScript 与 Swift 之间的双向通信能力
 * @performance 目标：单次调用延迟 < 300ms
 * @security 基于 macOS 安全策略的权限管理
 */

import Foundation
import WebKit

/// Bridge 调用结果
enum BridgeResult {
    case success(Any?)
    case failure(String)
}

/// Bridge 方法处理器协议
protocol BridgeHandler {
    var methodPrefix: String { get }
    func handle(method: String, params: [String: Any]) async -> BridgeResult
}

/// 主 Bridge 类
@MainActor
class SquirrelBridge: NSObject {

    // MARK: - Properties

    weak var webView: WKWebView?
    private var handlers: [BridgeHandler] = []
    private let performanceMonitor = BridgePerformanceMonitor()

    // 插件上下文
    private var pluginContext: [String: Any] = [:]

    // MARK: - Initialization

    init(webView: WKWebView) {
        self.webView = webView
        super.init()

        // 注册所有处理器
        registerHandlers()

        // 配置 WebView
        setupWebView()
    }

    private func registerHandlers() {
        handlers = [
            AIBridgeHandler(),
            RAGBridgeHandler(),
            FileBridgeHandler(),
            StorageBridgeHandler(),
            SystemBridgeHandler(),
            LogBridgeHandler(),
            AgentBridgeHandler(),
            MCPBridgeHandler()
        ]
    }

    private func setupWebView() {
        guard let webView = webView else { return }

        // 注册消息处理器
        webView.configuration.userContentController.add(self, name: "squirrelBridge")

        // 注入 Bridge SDK
        injectBridgeSDK()
    }

    // MARK: - Bridge SDK Injection

    private func injectBridgeSDK() {
        guard let webView = webView else { return }

        // 读取 Bridge SDK
        guard let sdkPath = Bundle.aiPlugins.path(forResource: "sdk_v2/squirrel-bridge", ofType: "js"),
              let sdkScript = try? String(contentsOfFile: sdkPath) else {
            print("[Bridge] ERROR: Failed to load Bridge SDK")
            return
        }

        // 注入上下文
        let contextScript = """
        window.__squirrel_context = \(contextJSON());
        window.SquirrelBridge = window.SquirrelBridge || {};
        window.SquirrelBridge.isDevelopment = false;
        """

        let script = WKUserScript(
            source: contextScript + "\n" + sdkScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )

        webView.configuration.userContentController.addUserScript(script)
        print("[Bridge] Bridge SDK injected successfully")
    }

    private func contextJSON() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: pluginContext),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Context Management

    func setPluginContext(id: String, name: String, version: String, userInput: String? = nil) {
        pluginContext = [
            "id": id,
            "name": name,
            "version": version,
            "userInput": userInput as Any
        ]
    }

    // MARK: - Event Dispatching

    /// 触发初始化事件
    func dispatchInitEvent() {
        dispatchEvent(name: "init", data: pluginContext)
    }

    /// 触发输入事件
    func dispatchInputEvent(text: String) {
        dispatchEvent(name: "input", data: ["text": text])
    }

    /// 触发销毁事件
    func dispatchDestroyEvent() {
        dispatchEvent(name: "destroy", data: nil)
    }

    /// 通用事件分发
    private func dispatchEvent(name: String, data: Any?) {
        guard let webView = webView else { return }

        let eventData = data ?? NSNull()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let script = """
        window.__squirrel_handleEvent({
            name: '\(name)',
            data: \(jsonString)
        });
        """

        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[Bridge] Error dispatching event '\(name)': \(error)")
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: [String: Any]) async {
        let startTime = Date()

        guard let id = message["id"] as? String,
              let method = message["method"] as? String else {
            print("[Bridge] Invalid message format")
            return
        }

        let params = message["params"] as? [String: Any] ?? [:]

        print("[Bridge] Handling: \(method)")

        // 查找处理器
        let result: BridgeResult
        if let handler = handlers.first(where: { method.hasPrefix($0.methodPrefix) }) {
            result = await handler.handle(method: method, params: params)
        } else {
            result = .failure("Unknown method: \(method)")
        }

        // 计算性能
        let duration = Date().timeIntervalSince(startTime) * 1000 // ms
        performanceMonitor.record(method: method, duration: duration)

        // 如果超过阈值，记录警告
        if duration > 300 {
            print("[Bridge] ⚠️ Performance warning: \(method) took \(String(format: "%.2f", duration))ms")
        }

        // 发送响应
        sendResponse(id: id, method: method, result: result)
    }

    private func sendResponse(id: String, method: String, result: BridgeResult) {
        guard let webView = webView else { return }

        let response: [String: Any]
        switch result {
        case .success(let data):
            response = [
                "id": id,
                "method": method,
                "result": data ?? NSNull()
            ]
        case .failure(let error):
            response = [
                "id": id,
                "method": method,
                "error": error
            ]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[Bridge] Failed to serialize response")
            return
        }

        let script = "window.__squirrel_handleResponse(\(jsonString));"

        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[Bridge] Error sending response: \(error)")
            }
        }
    }

    // MARK: - Stream Support

    func sendStreamChunk(streamId: String, chunk: String) {
        dispatchEvent(name: "stream.chunk", data: [
            "streamId": streamId,
            "chunk": chunk
        ])
    }

    func sendStreamComplete(streamId: String) {
        dispatchEvent(name: "stream.complete", data: [
            "streamId": streamId
        ])
    }

    func sendStreamError(streamId: String, error: String) {
        dispatchEvent(name: "stream.error", data: [
            "streamId": streamId,
            "error": error
        ])
    }

    // Agent Stream Support
    func sendAgentStreamChunk(streamId: String, chunk: Any) {
        dispatchEvent(name: "agent.stream.chunk", data: [
            "streamId": streamId,
            "chunk": chunk
        ])
    }

    func sendAgentStreamComplete(streamId: String, data: Any?) {
        dispatchEvent(name: "agent.stream.complete", data: [
            "streamId": streamId,
            "data": data as Any
        ])
    }

    func sendAgentStreamError(streamId: String, error: String) {
        dispatchEvent(name: "agent.stream.error", data: [
            "streamId": streamId,
            "error": error
        ])
    }

    // MCP Resource Update
    func sendMCPResourceUpdate(uri: String, resource: Any) {
        dispatchEvent(name: "mcp.resource.updated", data: [
            "uri": uri,
            "resource": resource
        ])
    }

    // MARK: - Performance Monitoring

    func getPerformanceStats() -> [String: Any] {
        return performanceMonitor.getStats()
    }
}

// MARK: - WKScriptMessageHandler

extension SquirrelBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "squirrelBridge",
              let body = message.body as? [String: Any] else {
            return
        }

        Task { @MainActor in
            await handleMessage(body)
        }
    }
}

// MARK: - Performance Monitor

class BridgePerformanceMonitor {
    private var records: [(method: String, duration: Double, timestamp: Date)] = []
    private let maxRecords = 100

    func record(method: String, duration: Double) {
        records.append((method, duration, Date()))

        // 保持记录数量在限制内
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    func getStats() -> [String: Any] {
        guard !records.isEmpty else {
            return ["count": 0]
        }

        let durations = records.map { $0.duration }
        let avg = durations.reduce(0, +) / Double(durations.count)
        let max = durations.max() ?? 0
        let min = durations.min() ?? 0

        let slowCalls = records.filter { $0.duration > 300 }

        return [
            "count": records.count,
            "average": avg,
            "max": max,
            "min": min,
            "slowCalls": slowCalls.count,
            "recentCalls": records.suffix(10).map { [
                "method": $0.method,
                "duration": $0.duration,
                "timestamp": $0.timestamp.timeIntervalSince1970
            ]}
        ]
    }
}
