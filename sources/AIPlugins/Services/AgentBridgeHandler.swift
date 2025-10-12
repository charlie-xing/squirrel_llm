/**
 * Agent Bridge Handler
 * 支持调用外部 AI Agent 的 Bridge 处理器
 */

import Foundation

// MARK: - Agent Configuration

struct AgentConfig: Codable {
    let id: String
    let name: String
    let description: String?
    let endpoint: String
    let auth: AuthConfig?
    let capabilities: [String]?
    let timeout: Int?
    let metadata: [String: AnyCodable]?
}

struct AuthConfig: Codable {
    let type: String // bearer, api_key, basic, custom
    let token: String?
    let apiKey: String?
    let username: String?
    let password: String?
    let headers: [String: String]?
}

// MARK: - Agent Bridge Handler

@MainActor
class AgentBridgeHandler: BridgeHandler {
    var methodPrefix: String { "agent." }

    private var registeredAgents: [String: AgentConfig] = [:]
    private let urlSession: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)

        // 加载已保存的 Agent 配置
        loadSavedAgents()
    }

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "agent.invoke":
            return await handleInvoke(params)
        case "agent.streamInvoke":
            return await handleStreamInvoke(params)
        case "agent.listAgents":
            return handleListAgents()
        case "agent.registerAgent":
            return await handleRegisterAgent(params)
        case "agent.unregisterAgent":
            return handleUnregisterAgent(params)
        case "agent.getAgent":
            return handleGetAgent(params)
        default:
            return .failure("Unknown agent method: \(method)")
        }
    }

    // MARK: - Invoke Agent

    private func handleInvoke(_ params: [String: Any]) async -> BridgeResult {
        guard let agentId = params["agent"] as? String,
              let action = params["action"] as? String else {
            return .failure("Missing required parameters: agent, action")
        }

        guard let agentConfig = registeredAgents[agentId] else {
            return .failure("Agent not found: \(agentId)")
        }

        let requestParams = params["params"] as? [String: Any] ?? [:]

        do {
            let response = try await invokeAgent(
                config: agentConfig,
                action: action,
                params: requestParams
            )

            return .success([
                "success": true,
                "data": response,
                "metadata": [
                    "agentId": agentId,
                    "action": action
                ]
            ])
        } catch {
            return .failure("Agent invocation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stream Invoke Agent

    private func handleStreamInvoke(_ params: [String: Any]) async -> BridgeResult {
        guard let streamId = params["streamId"] as? String,
              let agentId = params["agent"] as? String,
              let action = params["action"] as? String else {
            return .failure("Missing required parameters")
        }

        guard let agentConfig = registeredAgents[agentId] else {
            return .failure("Agent not found: \(agentId)")
        }

        let requestParams = params["params"] as? [String: Any] ?? [:]

        // 启动异步流式请求
        Task {
            do {
                try await streamInvokeAgent(
                    streamId: streamId,
                    config: agentConfig,
                    action: action,
                    params: requestParams
                )
            } catch {
                NotificationCenter.default.post(
                    name: .agentStreamError,
                    object: nil,
                    userInfo: ["streamId": streamId, "error": error.localizedDescription]
                )
            }
        }

        return .success(nil)
    }

    // MARK: - List Agents

    private func handleListAgents() -> BridgeResult {
        let agents = registeredAgents.values.map { agent in
            [
                "id": agent.id,
                "name": agent.name,
                "description": agent.description as Any,
                "endpoint": agent.endpoint,
                "capabilities": agent.capabilities as Any,
                "timeout": agent.timeout as Any
            ] as [String: Any]
        }
        return .success(agents)
    }

    // MARK: - Register Agent

    private func handleRegisterAgent(_ params: [String: Any]) async -> BridgeResult {
        guard let id = params["id"] as? String,
              let name = params["name"] as? String,
              let endpoint = params["endpoint"] as? String else {
            return .failure("Missing required parameters: id, name, endpoint")
        }

        // 创建 Agent 配置
        let authDict = params["auth"] as? [String: Any]
        let authConfig: AuthConfig? = authDict != nil ? try? JSONDecoder().decode(
            AuthConfig.self,
            from: JSONSerialization.data(withJSONObject: authDict!)
        ) : nil

        let config = AgentConfig(
            id: id,
            name: name,
            description: params["description"] as? String,
            endpoint: endpoint,
            auth: authConfig,
            capabilities: params["capabilities"] as? [String],
            timeout: params["timeout"] as? Int,
            metadata: nil
        )

        // 注册 Agent
        registeredAgents[id] = config
        saveAgents()

        print("[AgentBridge] Registered agent: \(name) (\(id))")
        return .success(nil)
    }

    // MARK: - Unregister Agent

    private func handleUnregisterAgent(_ params: [String: Any]) -> BridgeResult {
        guard let agentId = params["agentId"] as? String else {
            return .failure("Missing agentId parameter")
        }

        registeredAgents.removeValue(forKey: agentId)
        saveAgents()

        print("[AgentBridge] Unregistered agent: \(agentId)")
        return .success(nil)
    }

    // MARK: - Get Agent

    private func handleGetAgent(_ params: [String: Any]) -> BridgeResult {
        guard let agentId = params["agentId"] as? String else {
            return .failure("Missing agentId parameter")
        }

        guard let agent = registeredAgents[agentId] else {
            return .success(nil)
        }

        return .success([
            "id": agent.id,
            "name": agent.name,
            "description": agent.description as Any,
            "endpoint": agent.endpoint,
            "capabilities": agent.capabilities as Any,
            "timeout": agent.timeout as Any
        ])
    }

    // MARK: - HTTP Request Methods

    private func invokeAgent(
        config: AgentConfig,
        action: String,
        params: [String: Any]
    ) async throws -> Any {
        // 构建请求
        guard let url = URL(string: config.endpoint) else {
            throw NSError(domain: "AgentBridge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid endpoint URL"
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 添加认证
        if let auth = config.auth {
            applyAuth(to: &request, auth: auth)
        }

        // 构建请求体
        let requestBody: [String: Any] = [
            "action": action,
            "params": params
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 发送请求
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AgentBridge", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid HTTP response"
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AgentBridge", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"
            ])
        }

        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data)
        return json
    }

    private func streamInvokeAgent(
        streamId: String,
        config: AgentConfig,
        action: String,
        params: [String: Any]
    ) async throws {
        // 构建请求
        guard let url = URL(string: config.endpoint) else {
            throw NSError(domain: "AgentBridge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid endpoint URL"
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // 添加认证
        if let auth = config.auth {
            applyAuth(to: &request, auth: auth)
        }

        // 构建请求体
        let requestBody: [String: Any] = [
            "action": action,
            "params": params,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 发送流式请求
        let (asyncBytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AgentBridge", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "HTTP error"
            ])
        }

        // 处理流式响应
        var buffer = ""
        for try await byte in asyncBytes {
            let char = String(UnicodeScalar(byte))
            buffer += char

            // 检测换行，处理完整的行
            if char == "\n" {
                if buffer.hasPrefix("data: ") {
                    let jsonString = buffer.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                    if jsonString == "[DONE]" {
                        break
                    }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) {
                        // 发送 chunk
                        NotificationCenter.default.post(
                            name: .agentStreamChunk,
                            object: nil,
                            userInfo: ["streamId": streamId, "chunk": json]
                        )
                    }
                }
                buffer = ""
            }
        }

        // 完成
        NotificationCenter.default.post(
            name: .agentStreamComplete,
            object: nil,
            userInfo: ["streamId": streamId, "data": [:]]
        )
    }

    private func applyAuth(to request: inout URLRequest, auth: AuthConfig) {
        switch auth.type {
        case "bearer":
            if let token = auth.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case "api_key":
            if let apiKey = auth.apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            }
        case "basic":
            if let username = auth.username, let password = auth.password {
                let credentials = "\(username):\(password)"
                if let data = credentials.data(using: .utf8) {
                    let base64 = data.base64EncodedString()
                    request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
                }
            }
        case "custom":
            if let headers = auth.headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        default:
            break
        }
    }

    // MARK: - Persistence

    private func saveAgents() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Array(registeredAgents.values)) {
            UserDefaults.standard.set(data, forKey: "squirrel_registered_agents")
        }
    }

    private func loadSavedAgents() {
        guard let data = UserDefaults.standard.data(forKey: "squirrel_registered_agents") else {
            return
        }

        let decoder = JSONDecoder()
        if let agents = try? decoder.decode([AgentConfig].self, from: data) {
            for agent in agents {
                registeredAgents[agent.id] = agent
            }
            print("[AgentBridge] Loaded \(agents.count) saved agents")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let agentStreamChunk = Notification.Name("AgentStreamChunk")
    static let agentStreamComplete = Notification.Name("AgentStreamComplete")
    static let agentStreamError = Notification.Name("AgentStreamError")
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
