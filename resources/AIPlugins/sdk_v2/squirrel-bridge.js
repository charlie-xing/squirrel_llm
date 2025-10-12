/**
 * Squirrel Bridge SDK v2.0.0
 * 新一代插件架构 - JavaScript Bridge 实现
 *
 * @description 提供与 Swift 后端通信的标准化 API
 * @performance 目标：单次调用延迟 < 300ms
 */

(function(window) {
  'use strict';

  // ==================== 核心通信层 ====================

  const TIMEOUT_MS = 10000; // 10秒超时
  const PERFORMANCE_THRESHOLD_MS = 300; // 性能阈值

  let callId = 0;
  const pendingCalls = new Map();
  const performanceMarks = new Map();

  /**
   * 生成唯一调用 ID
   */
  function generateCallId() {
    return `call_${Date.now()}_${++callId}`;
  }

  /**
   * 调用 Swift 原生方法
   * @param {string} method - 方法名（如 'ai.chat'）
   * @param {object} params - 参数
   * @returns {Promise<any>} - 返回结果
   */
  async function callNative(method, params = {}) {
    const id = generateCallId();
    const startTime = performance.now();

    return new Promise((resolve, reject) => {
      // 设置超时
      const timeout = setTimeout(() => {
        pendingCalls.delete(id);
        reject(new Error(`Call timeout: ${method}`));
      }, TIMEOUT_MS);

      // 保存回调
      pendingCalls.set(id, { resolve, reject, timeout, startTime });

      // 发送消息到 Swift
      try {
        window.webkit.messageHandlers.squirrelBridge.postMessage({
          id,
          method,
          params,
          timestamp: Date.now()
        });
      } catch (error) {
        clearTimeout(timeout);
        pendingCalls.delete(id);
        reject(new Error(`Bridge communication failed: ${error.message}`));
      }
    });
  }

  /**
   * 处理来自 Swift 的响应
   * @param {object} response - 响应对象
   */
  function handleNativeResponse(response) {
    const { id, result, error } = response;
    const pending = pendingCalls.get(id);

    if (!pending) {
      console.warn('[Bridge] Received response for unknown call:', id);
      return;
    }

    const { resolve, reject, timeout, startTime } = pending;
    clearTimeout(timeout);
    pendingCalls.delete(id);

    // 性能监控
    const duration = performance.now() - startTime;
    if (duration > PERFORMANCE_THRESHOLD_MS) {
      console.warn(`[Bridge Performance] Slow call: ${response.method} took ${duration.toFixed(2)}ms`);
    }

    if (error) {
      reject(new Error(error));
    } else {
      resolve(result);
    }
  }

  /**
   * 处理来自 Swift 的事件
   * @param {object} event - 事件对象
   */
  function handleNativeEvent(event) {
    const customEvent = new CustomEvent(`squirrel:${event.name}`, {
      detail: event.data
    });
    window.dispatchEvent(customEvent);
  }

  // 注册全局响应处理器
  window.__squirrel_handleResponse = handleNativeResponse;
  window.__squirrel_handleEvent = handleNativeEvent;

  // ==================== Bridge API 实现 ====================

  const SquirrelBridge = {
    isDevelopment: false, // 将由 Swift 注入

    getContext() {
      return window.__squirrel_context || {
        id: 'unknown',
        name: 'Unknown Plugin',
        version: '0.0.0'
      };
    },

    // ==================== AI 能力 ====================

    AI: {
      async chat(options) {
        SquirrelBridge.Performance.mark('ai.chat.start');

        const result = await callNative('ai.chat', {
          prompt: options.prompt,
          systemPrompt: options.systemPrompt,
          temperature: options.temperature,
          maxTokens: options.maxTokens,
          model: options.model
        });

        SquirrelBridge.Performance.mark('ai.chat.end');
        SquirrelBridge.Performance.measure('ai.chat', 'ai.chat.start', 'ai.chat.end');

        return result;
      },

      async streamChat(options) {
        const streamId = generateCallId();

        // 注册流式事件监听器
        const chunkHandler = (e) => {
          if (e.detail.streamId === streamId && options.onChunk) {
            options.onChunk(e.detail.chunk);
          }
        };

        const completeHandler = (e) => {
          if (e.detail.streamId === streamId) {
            window.removeEventListener('squirrel:stream.chunk', chunkHandler);
            window.removeEventListener('squirrel:stream.complete', completeHandler);
            window.removeEventListener('squirrel:stream.error', errorHandler);
            if (options.onComplete) options.onComplete();
          }
        };

        const errorHandler = (e) => {
          if (e.detail.streamId === streamId) {
            window.removeEventListener('squirrel:stream.chunk', chunkHandler);
            window.removeEventListener('squirrel:stream.complete', completeHandler);
            window.removeEventListener('squirrel:stream.error', errorHandler);
            if (options.onError) options.onError(e.detail.error);
          }
        };

        window.addEventListener('squirrel:stream.chunk', chunkHandler);
        window.addEventListener('squirrel:stream.complete', completeHandler);
        window.addEventListener('squirrel:stream.error', errorHandler);

        // 启动流式请求
        await callNative('ai.streamChat', {
          streamId,
          prompt: options.prompt,
          systemPrompt: options.systemPrompt,
          temperature: options.temperature,
          maxTokens: options.maxTokens,
          model: options.model
        });
      },

      async listModels() {
        return await callNative('ai.listModels');
      },

      async getCurrentModel() {
        return await callNative('ai.getCurrentModel');
      }
    },

    // ==================== RAG 能力 ====================

    RAG: {
      async query(options) {
        return await callNative('rag.query', {
          text: options.text,
          knowledgeBase: options.knowledgeBase,
          topK: options.topK || 5,
          minSimilarity: options.minSimilarity || 0.7
        });
      },

      async listKnowledgeBases() {
        return await callNative('rag.listKnowledgeBases');
      },

      async embed(text) {
        return await callNative('rag.embed', { text });
      }
    },

    // ==================== 文件操作 ====================

    File: {
      async read(path) {
        return await callNative('file.read', { path });
      },

      async write(path, content) {
        return await callNative('file.write', { path, content });
      },

      async select(options = {}) {
        return await callNative('file.select', {
          allowedTypes: options.allowedTypes || [],
          allowMultiple: options.allowMultiple || false,
          message: options.message || 'Select a file'
        });
      },

      async getInfo(path) {
        return await callNative('file.getInfo', { path });
      }
    },

    // ==================== 本地存储 ====================

    Storage: {
      async get(key) {
        return await callNative('storage.get', { key });
      },

      async set(key, value) {
        return await callNative('storage.set', { key, value });
      },

      async remove(key) {
        return await callNative('storage.remove', { key });
      },

      async clear() {
        return await callNative('storage.clear');
      },

      async keys() {
        return await callNative('storage.keys');
      }
    },

    // ==================== 系统工具 ====================

    System: {
      async notify(options) {
        return await callNative('system.notify', {
          title: options.title,
          message: options.message,
          sound: options.sound !== false
        });
      },

      async openURL(url) {
        return await callNative('system.openURL', { url });
      },

      async copyToClipboard(text) {
        return await callNative('system.copyToClipboard', { text });
      },

      async getClipboard() {
        return await callNative('system.getClipboard');
      },

      async getSettings() {
        return await callNative('system.getSettings');
      }
    },

    // ==================== 生命周期钩子 ====================

    onInit(callback) {
      window.addEventListener('squirrel:init', (e) => {
        callback(e.detail);
      });
    },

    onInput(callback) {
      window.addEventListener('squirrel:input', (e) => {
        callback(e.detail.text);
      });
    },

    onDestroy(callback) {
      window.addEventListener('squirrel:destroy', callback);
    },

    // ==================== 性能监控 ====================

    Performance: {
      mark(name) {
        performanceMarks.set(name, performance.now());
      },

      measure(name, startMark, endMark) {
        const startTime = performanceMarks.get(startMark);
        const endTime = endMark ? performanceMarks.get(endMark) : performance.now();

        if (startTime === undefined) {
          console.warn(`[Performance] Start mark not found: ${startMark}`);
          return null;
        }

        const duration = endTime - startTime;
        const entry = {
          name,
          duration,
          timestamp: Date.now()
        };

        // 如果超过阈值，发出警告
        if (duration > PERFORMANCE_THRESHOLD_MS) {
          console.warn(`[Performance] ${name} took ${duration.toFixed(2)}ms (threshold: ${PERFORMANCE_THRESHOLD_MS}ms)`);
        }

        return entry;
      },

      getEntries() {
        return Array.from(performanceMarks.entries()).map(([name, timestamp]) => ({
          name,
          timestamp
        }));
      }
    },

    // ==================== 日志工具 ====================

    Log: {
      debug(message, ...args) {
        console.debug('[Plugin]', message, ...args);
        callNative('log.debug', { message, args }).catch(() => {});
      },

      info(message, ...args) {
        console.info('[Plugin]', message, ...args);
        callNative('log.info', { message, args }).catch(() => {});
      },

      warn(message, ...args) {
        console.warn('[Plugin]', message, ...args);
        callNative('log.warn', { message, args }).catch(() => {});
      },

      error(message, ...args) {
        console.error('[Plugin]', message, ...args);
        callNative('log.error', { message, args }).catch(() => {});
      }
    },

    // ==================== 外部 AI Agent ====================

    Agent: {
      async invoke(request) {
        SquirrelBridge.Performance.mark('agent.invoke.start');

        const result = await callNative('agent.invoke', {
          agent: request.agent,
          action: request.action,
          params: request.params,
          stream: request.stream || false
        });

        SquirrelBridge.Performance.mark('agent.invoke.end');
        SquirrelBridge.Performance.measure('agent.invoke', 'agent.invoke.start', 'agent.invoke.end');

        return result;
      },

      async streamInvoke(options) {
        const streamId = generateCallId();

        // 注册流式事件监听器
        const chunkHandler = (e) => {
          if (e.detail.streamId === streamId && options.onChunk) {
            options.onChunk(e.detail.chunk);
          }
        };

        const completeHandler = (e) => {
          if (e.detail.streamId === streamId) {
            window.removeEventListener('squirrel:agent.stream.chunk', chunkHandler);
            window.removeEventListener('squirrel:agent.stream.complete', completeHandler);
            window.removeEventListener('squirrel:agent.stream.error', errorHandler);
            if (options.onComplete) options.onComplete(e.detail.data);
          }
        };

        const errorHandler = (e) => {
          if (e.detail.streamId === streamId) {
            window.removeEventListener('squirrel:agent.stream.chunk', chunkHandler);
            window.removeEventListener('squirrel:agent.stream.complete', completeHandler);
            window.removeEventListener('squirrel:agent.stream.error', errorHandler);
            if (options.onError) options.onError(e.detail.error);
          }
        };

        window.addEventListener('squirrel:agent.stream.chunk', chunkHandler);
        window.addEventListener('squirrel:agent.stream.complete', completeHandler);
        window.addEventListener('squirrel:agent.stream.error', errorHandler);

        // 启动流式请求
        await callNative('agent.streamInvoke', {
          streamId,
          agent: options.agent,
          action: options.action,
          params: options.params
        });
      },

      async listAgents() {
        return await callNative('agent.listAgents');
      },

      async registerAgent(config) {
        return await callNative('agent.registerAgent', config);
      },

      async unregisterAgent(agentId) {
        return await callNative('agent.unregisterAgent', { agentId });
      },

      async getAgent(agentId) {
        return await callNative('agent.getAgent', { agentId });
      }
    },

    // ==================== MCP (Model Context Protocol) ====================

    MCP: {
      async getContext() {
        return await callNative('mcp.getContext');
      },

      async useTool(toolName, params) {
        SquirrelBridge.Performance.mark('mcp.useTool.start');

        const result = await callNative('mcp.useTool', {
          toolName,
          params
        });

        SquirrelBridge.Performance.mark('mcp.useTool.end');
        SquirrelBridge.Performance.measure('mcp.useTool', 'mcp.useTool.start', 'mcp.useTool.end');

        return result;
      },

      async getResource(uri) {
        return await callNative('mcp.getResource', { uri });
      },

      async listResources() {
        return await callNative('mcp.listResources');
      },

      async listTools() {
        return await callNative('mcp.listTools');
      },

      async listPrompts() {
        return await callNative('mcp.listPrompts');
      },

      async getPrompt(name, args = {}) {
        return await callNative('mcp.getPrompt', { name, args });
      },

      async subscribeResource(uri, callback) {
        // 注册订阅回调
        const handler = (e) => {
          if (e.detail.uri === uri) {
            callback(e.detail.resource);
          }
        };

        window.addEventListener('squirrel:mcp.resource.updated', handler);

        // 存储回调以便后续取消订阅
        if (!window.__mcp_subscriptions) {
          window.__mcp_subscriptions = new Map();
        }
        window.__mcp_subscriptions.set(uri, handler);

        return await callNative('mcp.subscribeResource', { uri });
      },

      async unsubscribeResource(uri) {
        // 移除事件监听器
        if (window.__mcp_subscriptions && window.__mcp_subscriptions.has(uri)) {
          const handler = window.__mcp_subscriptions.get(uri);
          window.removeEventListener('squirrel:mcp.resource.updated', handler);
          window.__mcp_subscriptions.delete(uri);
        }

        return await callNative('mcp.unsubscribeResource', { uri });
      }
    }
  };

  // 暴露到全局
  window.SquirrelBridge = SquirrelBridge;

  // 检测是否在浏览器环境（没有 webkit bridge）
  const isBrowserMode = !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.squirrelBridge;
  if (isBrowserMode) {
    console.log('[Bridge] Browser mode detected - enabling Mock API');
    SquirrelBridge.isDevelopment = true;
  }

  // 开发模式下的 Mock
  if (SquirrelBridge.isDevelopment) {
    console.log('[Bridge] Running in development mode with mocked APIs');

    // Mock AI API
    SquirrelBridge.AI.chat = async (options) => {
      await new Promise(resolve => setTimeout(resolve, 500));
      return {
        content: `Mock response for: ${options.prompt}`,
        model: 'mock-model',
        usage: { promptTokens: 10, completionTokens: 20, totalTokens: 30 }
      };
    };

    SquirrelBridge.AI.streamChat = async (options) => {
      const mockResponse = `Mock streaming response for: ${options.prompt}`;
      for (let i = 0; i < mockResponse.length; i++) {
        await new Promise(resolve => setTimeout(resolve, 50));
        if (options.onChunk) options.onChunk(mockResponse[i]);
      }
      if (options.onComplete) options.onComplete();
    };

    // Mock Storage API
    const mockStorage = new Map();
    SquirrelBridge.Storage.get = async (key) => mockStorage.get(key) || null;
    SquirrelBridge.Storage.set = async (key, value) => mockStorage.set(key, value);
    SquirrelBridge.Storage.remove = async (key) => mockStorage.delete(key);
    SquirrelBridge.Storage.clear = async () => mockStorage.clear();
    SquirrelBridge.Storage.keys = async () => Array.from(mockStorage.keys());

    // Mock Agent API
    const mockAgents = [
      {
        id: 'mock-agent-1',
        name: 'Mock Agent',
        description: 'A mock external agent',
        endpoint: 'http://localhost:3000',
        capabilities: ['chat', 'search']
      }
    ];

    SquirrelBridge.Agent.invoke = async (request) => {
      await new Promise(resolve => setTimeout(resolve, 300));
      return {
        success: true,
        data: { result: `Mock agent response for ${request.action}` },
        metadata: { executionTime: 300 }
      };
    };

    SquirrelBridge.Agent.streamInvoke = async (options) => {
      const mockData = ['chunk1', 'chunk2', 'chunk3'];
      for (const chunk of mockData) {
        await new Promise(resolve => setTimeout(resolve, 200));
        if (options.onChunk) options.onChunk(chunk);
      }
      if (options.onComplete) options.onComplete({ final: 'completed' });
    };

    SquirrelBridge.Agent.listAgents = async () => mockAgents;
    SquirrelBridge.Agent.registerAgent = async (config) => {
      mockAgents.push(config);
    };
    SquirrelBridge.Agent.unregisterAgent = async (agentId) => {
      const index = mockAgents.findIndex(a => a.id === agentId);
      if (index > -1) mockAgents.splice(index, 1);
    };
    SquirrelBridge.Agent.getAgent = async (agentId) => {
      return mockAgents.find(a => a.id === agentId) || null;
    };

    // Mock MCP API
    const mockMCPContext = {
      resources: [
        {
          uri: 'file:///mock/document.txt',
          name: 'Mock Document',
          type: 'text/plain',
          description: 'A mock document'
        }
      ],
      tools: [
        {
          name: 'mock_tool',
          description: 'A mock MCP tool',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string' }
            }
          }
        }
      ],
      prompts: [
        {
          name: 'mock_prompt',
          description: 'A mock prompt template',
          arguments: [
            { name: 'topic', required: true }
          ]
        }
      ],
      serverInfo: {
        name: 'Mock MCP Server',
        version: '1.0.0',
        protocolVersion: '2024-11-05'
      }
    };

    SquirrelBridge.MCP.getContext = async () => mockMCPContext;
    SquirrelBridge.MCP.useTool = async (toolName, params) => {
      await new Promise(resolve => setTimeout(resolve, 200));
      return {
        success: true,
        content: [
          {
            type: 'text',
            text: `Mock tool result for ${toolName} with params: ${JSON.stringify(params)}`
          }
        ]
      };
    };
    SquirrelBridge.MCP.getResource = async (uri) => {
      return {
        uri,
        mimeType: 'text/plain',
        text: 'Mock resource content'
      };
    };
    SquirrelBridge.MCP.listResources = async () => mockMCPContext.resources;
    SquirrelBridge.MCP.listTools = async () => mockMCPContext.tools;
    SquirrelBridge.MCP.listPrompts = async () => mockMCPContext.prompts;
    SquirrelBridge.MCP.getPrompt = async (name, args = {}) => {
      return {
        description: 'Mock prompt',
        messages: [
          {
            role: 'user',
            content: {
              type: 'text',
              text: `Mock prompt for ${name} with args: ${JSON.stringify(args)}`
            }
          }
        ]
      };
    };
    SquirrelBridge.MCP.subscribeResource = async (uri, callback) => {
      console.log(`[Mock MCP] Subscribed to resource: ${uri}`);
    };
    SquirrelBridge.MCP.unsubscribeResource = async (uri) => {
      console.log(`[Mock MCP] Unsubscribed from resource: ${uri}`);
    };
  }

  console.log('[Bridge] Squirrel Bridge SDK v2.0.0 loaded');

})(window);
