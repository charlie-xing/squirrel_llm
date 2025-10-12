/**
 * Squirrel Bridge API - TypeScript Definitions
 * @version 2.0.0
 * @description 新一代插件架构 Bridge API 类型定义
 */

declare namespace SquirrelBridge {
  /**
   * 判断是否在开发模式
   */
  const isDevelopment: boolean;

  /**
   * 插件元数据
   */
  interface PluginContext {
    id: string;
    name: string;
    version: string;
    userInput?: string;
  }

  /**
   * 获取插件上下文
   */
  function getContext(): PluginContext;

  // ==================== AI 能力 ====================

  namespace AI {
    interface ChatOptions {
      prompt: string;
      systemPrompt?: string;
      temperature?: number;
      maxTokens?: number;
      model?: string;
    }

    interface StreamChatOptions extends ChatOptions {
      onChunk?: (chunk: string) => void;
      onComplete?: () => void;
      onError?: (error: string) => void;
    }

    interface ChatResponse {
      content: string;
      model: string;
      usage?: {
        promptTokens: number;
        completionTokens: number;
        totalTokens: number;
      };
    }

    interface ModelInfo {
      id: string;
      name: string;
      provider: string;
      contextWindow: number;
    }

    /**
     * 普通对话（非流式）
     */
    function chat(options: ChatOptions): Promise<ChatResponse>;

    /**
     * 流式对话
     */
    function streamChat(options: StreamChatOptions): Promise<void>;

    /**
     * 获取可用模型列表
     */
    function listModels(): Promise<ModelInfo[]>;

    /**
     * 获取当前选择的模型
     */
    function getCurrentModel(): Promise<ModelInfo>;
  }

  // ==================== RAG 能力 ====================

  namespace RAG {
    interface QueryOptions {
      text: string;
      knowledgeBase: string;
      topK?: number;
      minSimilarity?: number;
    }

    interface RAGChunk {
      content: string;
      similarity: number;
      source: string;
      metadata?: Record<string, any>;
    }

    interface RAGResult {
      chunks: RAGChunk[];
      enhancedPrompt: string;
      averageSimilarity: number;
    }

    interface KnowledgeBase {
      id: string;
      name: string;
      description: string;
      documentCount: number;
      createdAt: string;
    }

    /**
     * 查询知识库
     */
    function query(options: QueryOptions): Promise<RAGResult>;

    /**
     * 获取知识库列表
     */
    function listKnowledgeBases(): Promise<KnowledgeBase[]>;

    /**
     * 向量嵌入
     */
    function embed(text: string): Promise<number[]>;
  }

  // ==================== 文件操作 ====================

  namespace File {
    interface SelectOptions {
      allowedTypes?: string[];
      allowMultiple?: boolean;
      message?: string;
    }

    interface FileInfo {
      path: string;
      name: string;
      size: number;
      extension: string;
    }

    /**
     * 读取文件内容
     */
    function read(path: string): Promise<string>;

    /**
     * 写入文件
     */
    function write(path: string, content: string): Promise<void>;

    /**
     * 选择文件对话框
     */
    function select(options?: SelectOptions): Promise<string[]>;

    /**
     * 获取文件信息
     */
    function getInfo(path: string): Promise<FileInfo>;
  }

  // ==================== 本地存储 ====================

  namespace Storage {
    /**
     * 获取存储的值
     */
    function get<T = any>(key: string): Promise<T | null>;

    /**
     * 设置存储的值
     */
    function set<T = any>(key: string, value: T): Promise<void>;

    /**
     * 删除存储的值
     */
    function remove(key: string): Promise<void>;

    /**
     * 清空所有存储
     */
    function clear(): Promise<void>;

    /**
     * 获取所有键
     */
    function keys(): Promise<string[]>;
  }

  // ==================== 系统工具 ====================

  namespace System {
    interface NotificationOptions {
      title: string;
      message: string;
      sound?: boolean;
    }

    /**
     * 显示系统通知
     */
    function notify(options: NotificationOptions): Promise<void>;

    /**
     * 打开 URL
     */
    function openURL(url: string): Promise<void>;

    /**
     * 复制到剪贴板
     */
    function copyToClipboard(text: string): Promise<void>;

    /**
     * 获取剪贴板内容
     */
    function getClipboard(): Promise<string>;

    /**
     * 获取用户设置
     */
    function getSettings(): Promise<Record<string, any>>;
  }

  // ==================== 生命周期钩子 ====================

  /**
   * 插件初始化时调用
   */
  function onInit(callback: (context: PluginContext) => void | Promise<void>): void;

  /**
   * 接收用户输入时调用
   */
  function onInput(callback: (text: string) => void | Promise<void>): void;

  /**
   * 插件销毁时调用
   */
  function onDestroy(callback: () => void | Promise<void>): void;

  // ==================== 性能监控 ====================

  namespace Performance {
    interface PerformanceEntry {
      name: string;
      duration: number;
      timestamp: number;
    }

    /**
     * 标记性能开始点
     */
    function mark(name: string): void;

    /**
     * 测量性能
     */
    function measure(name: string, startMark: string, endMark?: string): PerformanceEntry;

    /**
     * 获取性能条目
     */
    function getEntries(): PerformanceEntry[];
  }

  // ==================== 日志工具 ====================

  namespace Log {
    function debug(message: string, ...args: any[]): void;
    function info(message: string, ...args: any[]): void;
    function warn(message: string, ...args: any[]): void;
    function error(message: string, ...args: any[]): void;
  }

  // ==================== 外部 AI Agent ====================

  namespace Agent {
    /**
     * Agent 配置
     */
    interface AgentConfig {
      /** Agent 唯一标识 */
      id: string;
      /** Agent 名称 */
      name: string;
      /** Agent 描述 */
      description?: string;
      /** API 端点 */
      endpoint: string;
      /** 认证配置 */
      auth?: AuthConfig;
      /** Agent 支持的能力 */
      capabilities?: string[];
      /** 超时时间（毫秒） */
      timeout?: number;
      /** 自定义配置 */
      metadata?: Record<string, any>;
    }

    /**
     * 认证配置
     */
    interface AuthConfig {
      /** 认证类型: bearer, api_key, basic */
      type: 'bearer' | 'api_key' | 'basic' | 'custom';
      /** 认证令牌/密钥 */
      token?: string;
      /** API Key (用于 api_key 类型) */
      apiKey?: string;
      /** 用户名 (用于 basic 类型) */
      username?: string;
      /** 密码 (用于 basic 类型) */
      password?: string;
      /** 自定义请求头 */
      headers?: Record<string, string>;
    }

    /**
     * Agent 请求
     */
    interface AgentRequest {
      /** Agent ID */
      agent: string;
      /** 操作/动作 */
      action: string;
      /** 请求参数 */
      params: Record<string, any>;
      /** 是否流式响应 */
      stream?: boolean;
    }

    /**
     * Agent 响应
     */
    interface AgentResponse {
      /** 是否成功 */
      success: boolean;
      /** 响应数据 */
      data?: any;
      /** 错误信息 */
      error?: string;
      /** 响应元数据 */
      metadata?: Record<string, any>;
    }

    /**
     * 流式 Agent 请求选项
     */
    interface StreamAgentOptions extends AgentRequest {
      onChunk?: (chunk: any) => void;
      onComplete?: (finalData: any) => void;
      onError?: (error: string) => void;
    }

    /**
     * 调用外部 Agent
     */
    function invoke(request: AgentRequest): Promise<AgentResponse>;

    /**
     * 流式调用外部 Agent
     */
    function streamInvoke(options: StreamAgentOptions): Promise<void>;

    /**
     * 获取已注册的 Agent 列表
     */
    function listAgents(): Promise<AgentConfig[]>;

    /**
     * 注册新的 Agent
     */
    function registerAgent(config: AgentConfig): Promise<void>;

    /**
     * 取消注册 Agent
     */
    function unregisterAgent(agentId: string): Promise<void>;

    /**
     * 获取 Agent 配置
     */
    function getAgent(agentId: string): Promise<AgentConfig | null>;
  }

  // ==================== MCP (Model Context Protocol) ====================

  namespace MCP {
    /**
     * MCP 资源
     */
    interface Resource {
      /** 资源 URI */
      uri: string;
      /** 资源名称 */
      name: string;
      /** 资源类型 */
      type: string;
      /** 资源描述 */
      description?: string;
      /** MIME 类型 */
      mimeType?: string;
      /** 资源元数据 */
      metadata?: Record<string, any>;
    }

    /**
     * MCP 工具
     */
    interface Tool {
      /** 工具名称 */
      name: string;
      /** 工具描述 */
      description: string;
      /** 输入参数 Schema (JSON Schema) */
      inputSchema: Record<string, any>;
      /** 工具类型 */
      type?: string;
    }

    /**
     * MCP 提示词模板
     */
    interface Prompt {
      /** 提示词名称 */
      name: string;
      /** 提示词描述 */
      description?: string;
      /** 参数列表 */
      arguments?: PromptArgument[];
    }

    /**
     * 提示词参数
     */
    interface PromptArgument {
      /** 参数名称 */
      name: string;
      /** 参数描述 */
      description?: string;
      /** 是否必需 */
      required?: boolean;
    }

    /**
     * MCP 上下文
     */
    interface MCPContext {
      /** 可用资源列表 */
      resources: Resource[];
      /** 可用工具列表 */
      tools: Tool[];
      /** 可用提示词模板 */
      prompts: Prompt[];
      /** MCP 服务器信息 */
      serverInfo?: ServerInfo;
    }

    /**
     * MCP 服务器信息
     */
    interface ServerInfo {
      /** 服务器名称 */
      name: string;
      /** 服务器版本 */
      version: string;
      /** 协议版本 */
      protocolVersion: string;
      /** 服务器能力 */
      capabilities?: Record<string, any>;
    }

    /**
     * 工具调用结果
     */
    interface ToolResult {
      /** 是否成功 */
      success: boolean;
      /** 返回内容 */
      content: Array<{
        type: 'text' | 'image' | 'resource';
        text?: string;
        data?: string;
        mimeType?: string;
      }>;
      /** 是否有错误 */
      isError?: boolean;
    }

    /**
     * 资源内容
     */
    interface ResourceContent {
      /** 资源 URI */
      uri: string;
      /** 内容类型 */
      mimeType?: string;
      /** 文本内容 */
      text?: string;
      /** 二进制内容 (base64) */
      blob?: string;
    }

    /**
     * 获取 MCP 上下文
     */
    function getContext(): Promise<MCPContext>;

    /**
     * 使用 MCP 工具
     */
    function useTool(toolName: string, params: Record<string, any>): Promise<ToolResult>;

    /**
     * 获取资源内容
     */
    function getResource(uri: string): Promise<ResourceContent>;

    /**
     * 列出所有资源
     */
    function listResources(): Promise<Resource[]>;

    /**
     * 列出所有工具
     */
    function listTools(): Promise<Tool[]>;

    /**
     * 列出所有提示词模板
     */
    function listPrompts(): Promise<Prompt[]>;

    /**
     * 获取提示词
     */
    function getPrompt(name: string, args?: Record<string, string>): Promise<{
      description?: string;
      messages: Array<{
        role: 'user' | 'assistant';
        content: {
          type: 'text' | 'image' | 'resource';
          text?: string;
          data?: string;
          mimeType?: string;
        };
      }>;
    }>;

    /**
     * 订阅资源更新
     */
    function subscribeResource(uri: string, callback: (resource: Resource) => void): Promise<void>;

    /**
     * 取消订阅资源
     */
    function unsubscribeResource(uri: string): Promise<void>;
  }
}

/**
 * 全局 SquirrelBridge 对象
 */
declare const SquirrelBridge: typeof SquirrelBridge;

/**
 * 全局类型声明
 */
interface Window {
  SquirrelBridge: typeof SquirrelBridge;
}
