/**
 * MCP Bridge Handler
 * 支持 Model Context Protocol (MCP) 的 Bridge 处理器
 */

import Foundation

// MARK: - MCP Data Structures

struct MCPResource: Codable {
    let uri: String
    let name: String
    let type: String
    let description: String?
    let mimeType: String?
    let metadata: [String: AnyCodable]?
}

struct MCPTool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]
    let type: String?
}

struct MCPPrompt: Codable {
    let name: String
    let description: String?
    let arguments: [MCPPromptArgument]?
}

struct MCPPromptArgument: Codable {
    let name: String
    let description: String?
    let required: Bool?
}

struct MCPServerInfo: Codable {
    let name: String
    let version: String
    let protocolVersion: String
    let capabilities: [String: AnyCodable]?
}

struct MCPContext: Codable {
    let resources: [MCPResource]
    let tools: [MCPTool]
    let prompts: [MCPPrompt]
    let serverInfo: MCPServerInfo?
}

// MARK: - MCP Bridge Handler

@MainActor
class MCPBridgeHandler: BridgeHandler {
    var methodPrefix: String { "mcp." }

    private var mcpServers: [String: MCPServerConnection] = [:]
    private var resourceSubscriptions: [String: [String]] = [:] // uri -> [callbackIds]

    func handle(method: String, params: [String: Any]) async -> BridgeResult {
        switch method {
        case "mcp.getContext":
            return await handleGetContext()
        case "mcp.useTool":
            return await handleUseTool(params)
        case "mcp.getResource":
            return await handleGetResource(params)
        case "mcp.listResources":
            return await handleListResources()
        case "mcp.listTools":
            return await handleListTools()
        case "mcp.listPrompts":
            return await handleListPrompts()
        case "mcp.getPrompt":
            return await handleGetPrompt(params)
        case "mcp.subscribeResource":
            return await handleSubscribeResource(params)
        case "mcp.unsubscribeResource":
            return await handleUnsubscribeResource(params)
        default:
            return .failure("Unknown MCP method: \(method)")
        }
    }

    // MARK: - Get Context

    private func handleGetContext() async -> BridgeResult {
        // 聚合所有 MCP 服务器的上下文
        var allResources: [MCPResource] = []
        var allTools: [MCPTool] = []
        var allPrompts: [MCPPrompt] = []

        for (_, server) in mcpServers {
            if let context = try? await server.getContext() {
                allResources.append(contentsOf: context.resources)
                allTools.append(contentsOf: context.tools)
                allPrompts.append(contentsOf: context.prompts)
            }
        }

        let context = MCPContext(
            resources: allResources,
            tools: allTools,
            prompts: allPrompts,
            serverInfo: MCPServerInfo(
                name: "Squirrel MCP Aggregator",
                version: "1.0.0",
                protocolVersion: "2024-11-05",
                capabilities: nil
            )
        )

        return .success(try! encodeToDictionary(context))
    }

    // MARK: - Use Tool

    private func handleUseTool(_ params: [String: Any]) async -> BridgeResult {
        guard let toolName = params["toolName"] as? String else {
            return .failure("Missing toolName parameter")
        }

        let toolParams = params["params"] as? [String: Any] ?? [:]

        // 查找拥有该工具的服务器
        for (_, server) in mcpServers {
            if let tools = try? await server.listTools(),
               tools.contains(where: { $0.name == toolName }) {

                do {
                    let result = try await server.useTool(name: toolName, params: toolParams)
                    return .success(try encodeToDictionary(result))
                } catch {
                    return .failure("Tool execution failed: \(error.localizedDescription)")
                }
            }
        }

        return .failure("Tool not found: \(toolName)")
    }

    // MARK: - Get Resource

    private func handleGetResource(_ params: [String: Any]) async -> BridgeResult {
        guard let uri = params["uri"] as? String else {
            return .failure("Missing uri parameter")
        }

        // 查找拥有该资源的服务器
        for (_, server) in mcpServers {
            if let resources = try? await server.listResources(),
               resources.contains(where: { $0.uri == uri }) {

                do {
                    let content = try await server.getResource(uri: uri)
                    return .success([
                        "uri": content.uri,
                        "mimeType": content.mimeType as Any,
                        "text": content.text as Any,
                        "blob": content.blob as Any
                    ])
                } catch {
                    return .failure("Resource fetch failed: \(error.localizedDescription)")
                }
            }
        }

        return .failure("Resource not found: \(uri)")
    }

    // MARK: - List Resources

    private func handleListResources() async -> BridgeResult {
        var allResources: [MCPResource] = []

        for (_, server) in mcpServers {
            if let resources = try? await server.listResources() {
                allResources.append(contentsOf: resources)
            }
        }

        return .success(allResources.map { try! encodeToDictionary($0) })
    }

    // MARK: - List Tools

    private func handleListTools() async -> BridgeResult {
        var allTools: [MCPTool] = []

        for (_, server) in mcpServers {
            if let tools = try? await server.listTools() {
                allTools.append(contentsOf: tools)
            }
        }

        return .success(allTools.map { try! encodeToDictionary($0) })
    }

    // MARK: - List Prompts

    private func handleListPrompts() async -> BridgeResult {
        var allPrompts: [MCPPrompt] = []

        for (_, server) in mcpServers {
            if let prompts = try? await server.listPrompts() {
                allPrompts.append(contentsOf: prompts)
            }
        }

        return .success(allPrompts.map { try! encodeToDictionary($0) })
    }

    // MARK: - Get Prompt

    private func handleGetPrompt(_ params: [String: Any]) async -> BridgeResult {
        guard let name = params["name"] as? String else {
            return .failure("Missing name parameter")
        }

        let args = params["args"] as? [String: String] ?? [:]

        // 查找拥有该提示词的服务器
        for (_, server) in mcpServers {
            if let prompts = try? await server.listPrompts(),
               prompts.contains(where: { $0.name == name }) {

                do {
                    let prompt = try await server.getPrompt(name: name, args: args)
                    return .success(try encodeToDictionary(prompt))
                } catch {
                    return .failure("Prompt fetch failed: \(error.localizedDescription)")
                }
            }
        }

        return .failure("Prompt not found: \(name)")
    }

    // MARK: - Subscribe Resource

    private func handleSubscribeResource(_ params: [String: Any]) async -> BridgeResult {
        guard let uri = params["uri"] as? String else {
            return .failure("Missing uri parameter")
        }

        // 订阅资源更新
        // 这里简化实现，实际需要与 MCP 服务器建立 WebSocket 连接
        if resourceSubscriptions[uri] == nil {
            resourceSubscriptions[uri] = []
        }

        print("[MCPBridge] Subscribed to resource: \(uri)")
        return .success(nil)
    }

    // MARK: - Unsubscribe Resource

    private func handleUnsubscribeResource(_ params: [String: Any]) async -> BridgeResult {
        guard let uri = params["uri"] as? String else {
            return .failure("Missing uri parameter")
        }

        resourceSubscriptions.removeValue(forKey: uri)

        print("[MCPBridge] Unsubscribed from resource: \(uri)")
        return .success(nil)
    }

    // MARK: - Helper Methods

    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as! [String: Any]
    }

    // MARK: - Server Management

    func registerServer(id: String, connection: MCPServerConnection) {
        mcpServers[id] = connection
        print("[MCPBridge] Registered MCP server: \(id)")
    }

    func unregisterServer(id: String) {
        mcpServers.removeValue(forKey: id)
        print("[MCPBridge] Unregistered MCP server: \(id)")
    }
}

// MARK: - MCP Server Connection

class MCPServerConnection {
    let serverUrl: URL
    private let urlSession: URLSession

    init(serverUrl: URL) {
        self.serverUrl = serverUrl
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    func getContext() async throws -> MCPContext {
        let request = createRequest(endpoint: "/context")
        let (data, _) = try await urlSession.data(for: request)
        return try JSONDecoder().decode(MCPContext.self, from: data)
    }

    func listResources() async throws -> [MCPResource] {
        let request = createRequest(endpoint: "/resources")
        let (data, _) = try await urlSession.data(for: request)
        let response = try JSONDecoder().decode(ResourcesResponse.self, from: data)
        return response.resources
    }

    func listTools() async throws -> [MCPTool] {
        let request = createRequest(endpoint: "/tools")
        let (data, _) = try await urlSession.data(for: request)
        let response = try JSONDecoder().decode(ToolsResponse.self, from: data)
        return response.tools
    }

    func listPrompts() async throws -> [MCPPrompt] {
        let request = createRequest(endpoint: "/prompts")
        let (data, _) = try await urlSession.data(for: request)
        let response = try JSONDecoder().decode(PromptsResponse.self, from: data)
        return response.prompts
    }

    func useTool(name: String, params: [String: Any]) async throws -> MCPToolResult {
        var request = createRequest(endpoint: "/tools/use")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "params": params
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await urlSession.data(for: request)
        return try JSONDecoder().decode(MCPToolResult.self, from: data)
    }

    func getResource(uri: String) async throws -> MCPResourceContent {
        var request = createRequest(endpoint: "/resources/get")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["uri": uri]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await urlSession.data(for: request)
        return try JSONDecoder().decode(MCPResourceContent.self, from: data)
    }

    func getPrompt(name: String, args: [String: String]) async throws -> MCPPromptResult {
        var request = createRequest(endpoint: "/prompts/get")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "arguments": args
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await urlSession.data(for: request)
        return try JSONDecoder().decode(MCPPromptResult.self, from: data)
    }

    private func createRequest(endpoint: String) -> URLRequest {
        let url = serverUrl.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

// MARK: - Response Types

struct ResourcesResponse: Codable {
    let resources: [MCPResource]
}

struct ToolsResponse: Codable {
    let tools: [MCPTool]
}

struct PromptsResponse: Codable {
    let prompts: [MCPPrompt]
}

struct MCPToolResult: Codable {
    let success: Bool
    let content: [MCPContent]
    let isError: Bool?
}

struct MCPContent: Codable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
}

struct MCPResourceContent: Codable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?
}

struct MCPPromptResult: Codable {
    let description: String?
    let messages: [MCPMessage]
}

struct MCPMessage: Codable {
    let role: String
    let content: MCPContent
}
