# Agent & MCP API 使用指南

## 📋 概述

Squirrel Bridge v2.0 现在支持调用外部 AI Agent 和 Model Context Protocol (MCP)，让插件能够：

- 🤖 **调用外部 AI Agent**: 集成第三方 AI 服务和自定义 Agent
- 🔌 **支持 MCP 协议**: 访问 MCP 服务器提供的资源、工具和提示词
- 📡 **流式响应**: 支持实时流式数据处理
- 🔐 **灵活认证**: 支持多种认证方式（Bearer, API Key, Basic, Custom）

---

## 🤖 外部 AI Agent

### 1. 注册 Agent

在使用 Agent 之前，需要先注册：

```javascript
await SquirrelBridge.Agent.registerAgent({
    id: 'my-custom-agent',
    name: 'My Custom Agent',
    description: '一个自定义 AI Agent',
    endpoint: 'https://api.example.com/agent',
    auth: {
        type: 'bearer',
        token: 'your-api-token'
    },
    capabilities: ['chat', 'search', 'analyze'],
    timeout: 30000
});
```

### 2. 调用 Agent（非流式）

```javascript
const response = await SquirrelBridge.Agent.invoke({
    agent: 'my-custom-agent',
    action: 'chat',
    params: {
        message: '你好，请帮我分析这段文本',
        context: { language: 'zh-CN' }
    }
});

if (response.success) {
    console.log('Agent 响应:', response.data);
} else {
    console.error('Agent 错误:', response.error);
}
```

### 3. 流式调用 Agent

```javascript
await SquirrelBridge.Agent.streamInvoke({
    agent: 'my-custom-agent',
    action: 'generate',
    params: {
        prompt: '写一首关于春天的诗'
    },
    onChunk: (chunk) => {
        // 实时接收数据块
        console.log('收到:', chunk);
        appendToUI(chunk);
    },
    onComplete: (finalData) => {
        console.log('完成:', finalData);
    },
    onError: (error) => {
        console.error('错误:', error);
    }
});
```

### 4. 管理 Agent

```javascript
// 列出所有已注册的 Agent
const agents = await SquirrelBridge.Agent.listAgents();
agents.forEach(agent => {
    console.log(`${agent.name}: ${agent.endpoint}`);
});

// 获取特定 Agent 的配置
const agent = await SquirrelBridge.Agent.getAgent('my-custom-agent');
if (agent) {
    console.log('Agent 能力:', agent.capabilities);
}

// 取消注册 Agent
await SquirrelBridge.Agent.unregisterAgent('my-custom-agent');
```

---

## 🔌 Model Context Protocol (MCP)

### 1. 获取 MCP 上下文

```javascript
const context = await SquirrelBridge.MCP.getContext();

console.log('可用资源:', context.resources);
console.log('可用工具:', context.tools);
console.log('可用提示词:', context.prompts);
console.log('服务器信息:', context.serverInfo);
```

### 2. 使用 MCP 工具

```javascript
// 列出所有可用工具
const tools = await SquirrelBridge.MCP.listTools();
tools.forEach(tool => {
    console.log(`工具: ${tool.name} - ${tool.description}`);
});

// 调用工具
const result = await SquirrelBridge.MCP.useTool('search', {
    query: '机器学习',
    limit: 10
});

if (result.success) {
    result.content.forEach(item => {
        if (item.type === 'text') {
            console.log(item.text);
        }
    });
}
```

### 3. 访问 MCP 资源

```javascript
// 列出所有资源
const resources = await SquirrelBridge.MCP.listResources();
resources.forEach(resource => {
    console.log(`${resource.name} (${resource.uri}): ${resource.description}`);
});

// 获取资源内容
const content = await SquirrelBridge.MCP.getResource('file:///documents/readme.txt');
console.log('资源内容:', content.text);
```

### 4. 使用提示词模板

```javascript
// 列出所有提示词
const prompts = await SquirrelBridge.MCP.listPrompts();
prompts.forEach(prompt => {
    console.log(`${prompt.name}: ${prompt.description}`);
});

// 获取提示词
const promptResult = await SquirrelBridge.MCP.getPrompt('code_review', {
    language: 'javascript',
    file: 'app.js'
});

// 使用提示词进行 AI 对话
const aiResponse = await SquirrelBridge.AI.chat({
    prompt: promptResult.messages[0].content.text
});
```

### 5. 订阅资源更新

```javascript
// 订阅资源更新通知
await SquirrelBridge.MCP.subscribeResource(
    'file:///watch/config.json',
    (resource) => {
        console.log('资源已更新:', resource);
        reloadConfig();
    }
);

// 取消订阅
await SquirrelBridge.MCP.unsubscribeResource('file:///watch/config.json');
```

---

## 🔐 认证配置

### Bearer Token

```javascript
auth: {
    type: 'bearer',
    token: 'your-bearer-token'
}
```

### API Key

```javascript
auth: {
    type: 'api_key',
    apiKey: 'your-api-key'
}
```

### Basic Auth

```javascript
auth: {
    type: 'basic',
    username: 'user',
    password: 'pass'
}
```

### 自定义请求头

```javascript
auth: {
    type: 'custom',
    headers: {
        'X-Custom-Auth': 'custom-value',
        'X-Request-ID': 'req-123'
    }
}
```

---

## 📊 完整示例：智能文档分析插件

```html
<!DOCTYPE html>
<html>
<head>
    <title>智能文档分析</title>
</head>
<body>
    <h1>智能文档分析</h1>

    <div>
        <h2>1. 选择文档</h2>
        <button onclick="selectDocument()">选择文档</button>
        <div id="doc-info"></div>
    </div>

    <div>
        <h2>2. 使用 MCP 工具分析</h2>
        <button onclick="analyzeWithMCP()">MCP 分析</button>
    </div>

    <div>
        <h2>3. 使用外部 Agent 分析</h2>
        <button onclick="analyzeWithAgent()">Agent 分析</button>
    </div>

    <div>
        <h2>结果</h2>
        <pre id="results"></pre>
    </div>

    <script>
        let selectedFile = null;

        // 初始化
        SquirrelBridge.onInit(async (context) => {
            // 注册自定义 Agent
            await SquirrelBridge.Agent.registerAgent({
                id: 'document-analyzer',
                name: 'Document Analyzer',
                endpoint: 'https://api.example.com/analyze',
                auth: {
                    type: 'api_key',
                    apiKey: 'your-api-key'
                },
                capabilities: ['analyze', 'summarize']
            });

            // 获取 MCP 上下文
            const mcpContext = await SquirrelBridge.MCP.getContext();
            console.log('MCP 工具:', mcpContext.tools);
        });

        // 选择文档
        async function selectDocument() {
            const files = await SquirrelBridge.File.select({
                allowedTypes: ['txt', 'md', 'pdf'],
                message: '选择要分析的文档'
            });

            if (files.length > 0) {
                selectedFile = files[0];
                const content = await SquirrelBridge.File.read(selectedFile);

                document.getElementById('doc-info').innerHTML = `
                    <p>已选择: ${selectedFile}</p>
                    <p>长度: ${content.length} 字符</p>
                `;
            }
        }

        // 使用 MCP 工具分析
        async function analyzeWithMCP() {
            if (!selectedFile) {
                alert('请先选择文档');
                return;
            }

            const results = document.getElementById('results');
            results.textContent = '正在使用 MCP 工具分析...\n';

            try {
                // 使用 MCP 的文档分析工具
                const result = await SquirrelBridge.MCP.useTool('analyze_document', {
                    path: selectedFile,
                    options: {
                        extractKeywords: true,
                        summarize: true
                    }
                });

                if (result.success) {
                    result.content.forEach(item => {
                        if (item.type === 'text') {
                            results.textContent += '\n' + item.text;
                        }
                    });
                }
            } catch (error) {
                results.textContent += '\n错误: ' + error.message;
            }
        }

        // 使用外部 Agent 分析
        async function analyzeWithAgent() {
            if (!selectedFile) {
                alert('请先选择文档');
                return;
            }

            const results = document.getElementById('results');
            results.textContent = '正在使用 Agent 分析...\n';

            const content = await SquirrelBridge.File.read(selectedFile);

            // 流式分析
            await SquirrelBridge.Agent.streamInvoke({
                agent: 'document-analyzer',
                action: 'analyze',
                params: {
                    content: content,
                    language: 'zh-CN'
                },
                onChunk: (chunk) => {
                    results.textContent += chunk;
                },
                onComplete: () => {
                    results.textContent += '\n\n分析完成！';
                },
                onError: (error) => {
                    results.textContent += '\n错误: ' + error;
                }
            });
        }
    </script>
</body>
</html>
```

---

## 🎯 最佳实践

### 1. 错误处理

```javascript
try {
    const response = await SquirrelBridge.Agent.invoke({...});

    if (!response.success) {
        // Agent 返回了错误
        SquirrelBridge.Log.error('Agent error:', response.error);
        SquirrelBridge.System.notify({
            title: '操作失败',
            message: response.error
        });
        return;
    }

    // 处理成功响应
    processResponse(response.data);

} catch (error) {
    // 网络或其他错误
    SquirrelBridge.Log.error('Exception:', error);
}
```

### 2. 超时处理

```javascript
// 注册 Agent 时设置超时
await SquirrelBridge.Agent.registerAgent({
    id: 'slow-agent',
    timeout: 60000, // 60秒超时
    // ...
});

// 使用 Promise.race 实现自定义超时
const timeoutPromise = new Promise((_, reject) => {
    setTimeout(() => reject(new Error('操作超时')), 10000);
});

const response = await Promise.race([
    SquirrelBridge.Agent.invoke({...}),
    timeoutPromise
]);
```

### 3. 性能监控

```javascript
SquirrelBridge.Performance.mark('agent.start');

const response = await SquirrelBridge.Agent.invoke({...});

SquirrelBridge.Performance.mark('agent.end');
const perf = SquirrelBridge.Performance.measure(
    'Agent Call',
    'agent.start',
    'agent.end'
);

if (perf.duration > 1000) {
    SquirrelBridge.Log.warn('Agent 响应较慢:', perf.duration);
}
```

### 4. 缓存策略

```javascript
// 缓存 Agent 响应
const cacheKey = `agent_${agentId}_${action}_${JSON.stringify(params)}`;
let cached = await SquirrelBridge.Storage.get(cacheKey);

if (cached) {
    return cached;
}

const response = await SquirrelBridge.Agent.invoke({...});

// 缓存 5 分钟
await SquirrelBridge.Storage.set(cacheKey, {
    data: response,
    timestamp: Date.now(),
    ttl: 5 * 60 * 1000
});
```

---

## 🔧 故障排除

### Agent 连接失败

1. 检查 endpoint URL 是否正确
2. 验证认证配置
3. 确认网络连接
4. 查看 Console 日志

### MCP 工具不可用

1. 确认 MCP 服务器已启动
2. 检查工具名称是否正确
3. 验证参数格式
4. 查看 `getContext()` 返回的可用工具列表

### 流式响应中断

1. 检查网络稳定性
2. 确认服务器支持流式响应
3. 增加超时时间
4. 添加重试逻辑

---

## 📚 参考资源

- [Bridge API 完整文档](./README.md)
- [MCP 协议规范](https://modelcontextprotocol.io)
- [示例插件库](../modern_chat_v2/)
- [TypeScript 类型定义](./squirrel-bridge.d.ts)

---

**更新日期**: 2025-10-12
**版本**: v2.0.0
