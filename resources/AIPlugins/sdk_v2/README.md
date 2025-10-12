# Squirrel Bridge API v2.0 - 新一代插件架构

## 📖 概述

Squirrel Bridge v2.0 是全新设计的插件架构，提供简洁、强大、高性能的插件开发体验。

### 核心特性

- ✅ **极简开发**：插件就是一个 HTML 文件，无需复杂继承
- ✅ **TypeScript 支持**：完整的类型定义，开发更安全
- ✅ **高性能**：单次调用延迟 < 300ms，内置性能监控
- ✅ **安全可控**：基于 macOS 安全策略的权限管理
- ✅ **标准化 API**：统一的 Bridge API，易学易用
- 🆕 **外部 Agent 集成**：调用第三方 AI Agent 和自定义服务
- 🆕 **MCP 协议支持**：访问 MCP 服务器的资源、工具和提示词

### 与旧架构对比

| 特性 | 旧架构 (v1) | 新架构 (v2) |
|------|------------|------------|
| 开发复杂度 | 需要继承 ChatPlugin，理解生命周期 | 纯 HTML + JavaScript，即写即用 |
| 代码量 | ~300-500 行 | ~100-200 行 |
| 调试方式 | WebView 内调试，较困难 | 浏览器独立调试 + Mock API |
| 性能监控 | 无 | 内置性能监控和警告 |
| TypeScript | 不支持 | 完整类型定义 |

---

## 🚀 快速开始

### 1. 插件结构

```
my_plugin/
├── config.json       # 插件配置
└── index.html        # 主入口文件
```

### 2. 最小示例

**config.json**
```json
{
  "id": "com.example.hello",
  "name": "Hello Plugin",
  "version": "1.0.0",
  "description": "My first plugin",
  "capabilities": {
    "ai": ["chat"],
    "storage": ["local"]
  },
  "entry": "index.html"
}
```

**index.html**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Hello Plugin</title>
</head>
<body>
    <h1>Hello Squirrel!</h1>
    <button onclick="chat()">Chat with AI</button>
    <div id="response"></div>

    <script>
        async function chat() {
            const response = await SquirrelBridge.AI.chat({
                prompt: "Hello, how are you?"
            });
            document.getElementById('response').textContent = response.content;
        }

        // 初始化
        SquirrelBridge.onInit((context) => {
            console.log('Plugin loaded:', context);
        });
    </script>
</body>
</html>
```

---

## 📚 API 文档

### 生命周期

#### `SquirrelBridge.onInit(callback)`
插件初始化时调用

```javascript
SquirrelBridge.onInit((context) => {
    console.log('Plugin ID:', context.id);
    console.log('User input:', context.userInput);
});
```

#### `SquirrelBridge.onInput(callback)`
接收用户输入时调用

```javascript
SquirrelBridge.onInput((text) => {
    console.log('User typed:', text);
    // 自动填充到输入框
});
```

#### `SquirrelBridge.onDestroy(callback)`
插件销毁前调用

```javascript
SquirrelBridge.onDestroy(() => {
    // 清理资源、保存状态
});
```

---

### AI 能力

#### `AI.chat(options)`
普通对话（非流式）

```javascript
const response = await SquirrelBridge.AI.chat({
    prompt: "你好",
    systemPrompt: "你是一个友好的助手",  // 可选
    temperature: 0.7,                     // 可选
    maxTokens: 2000,                      // 可选
    model: "gpt-4"                        // 可选
});

console.log(response.content);
console.log(response.usage.totalTokens);
```

#### `AI.streamChat(options)`
流式对话

```javascript
await SquirrelBridge.AI.streamChat({
    prompt: "讲个故事",
    onChunk: (chunk) => {
        // 实时接收每个字符
        console.log(chunk);
    },
    onComplete: () => {
        console.log('Stream完成');
    },
    onError: (error) => {
        console.error('错误:', error);
    }
});
```

#### `AI.listModels()`
获取可用模型列表

```javascript
const models = await SquirrelBridge.AI.listModels();
models.forEach(model => {
    console.log(`${model.name} (${model.provider})`);
});
```

#### `AI.getCurrentModel()`
获取当前选择的模型

```javascript
const model = await SquirrelBridge.AI.getCurrentModel();
console.log('当前模型:', model.name);
```

---

### RAG 能力

#### `RAG.query(options)`
查询知识库

```javascript
const result = await SquirrelBridge.RAG.query({
    text: "什么是机器学习？",
    knowledgeBase: "AI百科",
    topK: 5,              // 可选，默认 5
    minSimilarity: 0.7    // 可选，默认 0.7
});

console.log('增强后的提示:', result.enhancedPrompt);
result.chunks.forEach(chunk => {
    console.log(`${chunk.source}: ${chunk.content} (相似度: ${chunk.similarity})`);
});
```

#### `RAG.listKnowledgeBases()`
获取知识库列表

```javascript
const kbs = await SquirrelBridge.RAG.listKnowledgeBases();
kbs.forEach(kb => {
    console.log(`${kb.name}: ${kb.documentCount} 文档`);
});
```

#### `RAG.embed(text)`
文本向量化

```javascript
const embedding = await SquirrelBridge.RAG.embed("Hello world");
console.log('向量维度:', embedding.length);
```

---

### 文件操作

#### `File.read(path)`
读取文件

```javascript
const content = await SquirrelBridge.File.read('/path/to/file.txt');
console.log(content);
```

#### `File.write(path, content)`
写入文件

```javascript
await SquirrelBridge.File.write('/path/to/file.txt', 'Hello World');
```

#### `File.select(options)`
选择文件对话框

```javascript
const paths = await SquirrelBridge.File.select({
    allowedTypes: ['txt', 'md'],
    allowMultiple: true,
    message: '选择文件'
});
console.log('已选择:', paths);
```

#### `File.getInfo(path)`
获取文件信息

```javascript
const info = await SquirrelBridge.File.getInfo('/path/to/file.txt');
console.log(`文件名: ${info.name}, 大小: ${info.size} bytes`);
```

---

### 本地存储

#### `Storage.get(key)`
获取存储值

```javascript
const value = await SquirrelBridge.Storage.get('myKey');
console.log(value);
```

#### `Storage.set(key, value)`
设置存储值

```javascript
await SquirrelBridge.Storage.set('myKey', { foo: 'bar' });
```

#### `Storage.remove(key)`
删除存储值

```javascript
await SquirrelBridge.Storage.remove('myKey');
```

#### `Storage.clear()`
清空所有存储

```javascript
await SquirrelBridge.Storage.clear();
```

#### `Storage.keys()`
获取所有键

```javascript
const keys = await SquirrelBridge.Storage.keys();
console.log('存储的键:', keys);
```

---

### 系统工具

#### `System.notify(options)`
显示系统通知

```javascript
await SquirrelBridge.System.notify({
    title: '提示',
    message: '操作完成！',
    sound: true
});
```

#### `System.openURL(url)`
打开 URL

```javascript
await SquirrelBridge.System.openURL('https://example.com');
```

#### `System.copyToClipboard(text)`
复制到剪贴板

```javascript
await SquirrelBridge.System.copyToClipboard('Hello World');
```

#### `System.getClipboard()`
获取剪贴板内容

```javascript
const text = await SquirrelBridge.System.getClipboard();
console.log(text);
```

#### `System.getSettings()`
获取用户设置

```javascript
const settings = await SquirrelBridge.System.getSettings();
console.log('用户名:', settings.userName);
```

---

### 性能监控

#### `Performance.mark(name)`
标记性能点

```javascript
SquirrelBridge.Performance.mark('operation.start');
// ... 执行操作 ...
SquirrelBridge.Performance.mark('operation.end');
```

#### `Performance.measure(name, startMark, endMark)`
测量性能

```javascript
const entry = SquirrelBridge.Performance.measure(
    'Operation Duration',
    'operation.start',
    'operation.end'
);
console.log(`耗时: ${entry.duration.toFixed(2)}ms`);
```

#### `Performance.getEntries()`
获取所有性能条目

```javascript
const entries = SquirrelBridge.Performance.getEntries();
entries.forEach(e => {
    console.log(`${e.name}: ${e.timestamp}ms`);
});
```

---

### 日志工具

#### `Log.debug/info/warn/error(message, ...args)`
记录日志

```javascript
SquirrelBridge.Log.debug('调试信息', { foo: 'bar' });
SquirrelBridge.Log.info('普通信息');
SquirrelBridge.Log.warn('警告信息');
SquirrelBridge.Log.error('错误信息', error);
```

---

### 🤖 外部 AI Agent（新功能）

#### `Agent.registerAgent(config)`
注册外部 Agent

```javascript
await SquirrelBridge.Agent.registerAgent({
    id: 'custom-agent',
    name: 'Custom Agent',
    endpoint: 'https://api.example.com/agent',
    auth: {
        type: 'bearer',
        token: 'your-token'
    }
});
```

#### `Agent.invoke(request)`
调用 Agent

```javascript
const response = await SquirrelBridge.Agent.invoke({
    agent: 'custom-agent',
    action: 'analyze',
    params: { text: 'Hello' }
});

console.log(response.data);
```

#### `Agent.streamInvoke(options)`
流式调用 Agent

```javascript
await SquirrelBridge.Agent.streamInvoke({
    agent: 'custom-agent',
    action: 'generate',
    params: { prompt: 'Write a poem' },
    onChunk: (chunk) => console.log(chunk),
    onComplete: (data) => console.log('Done!', data)
});
```

**📚 详细文档**: [Agent & MCP 使用指南](./AGENT_MCP_GUIDE.md)

---

### 🔌 Model Context Protocol（新功能）

#### `MCP.getContext()`
获取 MCP 上下文

```javascript
const context = await SquirrelBridge.MCP.getContext();
console.log('可用工具:', context.tools);
console.log('可用资源:', context.resources);
```

#### `MCP.useTool(name, params)`
使用 MCP 工具

```javascript
const result = await SquirrelBridge.MCP.useTool('search', {
    query: '机器学习'
});
console.log(result.content);
```

#### `MCP.getResource(uri)`
获取 MCP 资源

```javascript
const content = await SquirrelBridge.MCP.getResource('file:///docs/readme.txt');
console.log(content.text);
```

**📚 详细文档**: [Agent & MCP 使用指南](./AGENT_MCP_GUIDE.md)

---

## 🎨 最佳实践

### 1. 使用 TypeScript

创建 `index.ts`：

```typescript
/// <reference path="../../sdk_v2/squirrel-bridge.d.ts" />

interface Message {
    role: 'user' | 'assistant';
    content: string;
}

const messages: Message[] = [];

async function sendMessage(text: string) {
    messages.push({ role: 'user', content: text });

    const response = await SquirrelBridge.AI.chat({
        prompt: text
    });

    messages.push({ role: 'assistant', content: response.content });
}
```

### 2. 错误处理

```javascript
try {
    await SquirrelBridge.AI.chat({ prompt: "Hello" });
} catch (error) {
    SquirrelBridge.Log.error('AI调用失败:', error);
    SquirrelBridge.System.notify({
        title: '错误',
        message: error.message
    });
}
```

### 3. 性能优化

```javascript
// 标记关键操作
SquirrelBridge.Performance.mark('render.start');
renderMessages();
SquirrelBridge.Performance.mark('render.end');

// 测量并记录
const perf = SquirrelBridge.Performance.measure('Render', 'render.start', 'render.end');
if (perf.duration > 100) {
    SquirrelBridge.Log.warn('渲染性能慢:', perf.duration);
}
```

### 4. 状态持久化

```javascript
// 保存状态
async function saveState() {
    await SquirrelBridge.Storage.set('appState', {
        messages,
        lastUpdated: Date.now()
    });
}

// 加载状态
async function loadState() {
    const state = await SquirrelBridge.Storage.get('appState');
    if (state) {
        messages.push(...state.messages);
    }
}

// 在关闭时保存
SquirrelBridge.onDestroy(() => {
    saveState();
});
```

---

## 🔧 开发模式

在开发模式下，Bridge API 会提供 Mock 数据，允许你在浏览器中独立开发调试。

```html
<!DOCTYPE html>
<html>
<head>
    <script src="../../sdk_v2/squirrel-bridge.js"></script>
    <script>
        // 启用开发模式
        window.SquirrelBridge = window.SquirrelBridge || {};
        window.SquirrelBridge.isDevelopment = true;
    </script>
</head>
<body>
    <!-- 现在可以在浏览器中直接打开测试 -->
</body>
</html>
```

---

## 📊 性能目标

- **初始化**: < 100ms
- **API 调用**: < 300ms
- **流式响应首字**: < 500ms
- **UI 渲染**: < 16ms (60 FPS)

超过阈值的调用会自动记录警告日志。

---

## 🔐 安全策略

### 权限声明

在 `config.json` 中声明所需权限：

```json
{
  "capabilities": {
    "ai": ["chat", "stream"],      // AI 能力
    "storage": ["local"],           // 本地存储
    "rag": true,                    // RAG 能力
    "fileAccess": false             // 文件访问（需要用户授权）
  }
}
```

### 沙箱隔离

- 每个插件运行在独立的 WebView 中
- 不能访问其他插件的数据
- 不能访问未声明权限的 API

---

## 🚀 示例插件

查看 `modern_chat_v2` 目录获取完整示例：

- **现代聊天**: 展示 AI 流式对话、Storage 持久化
- **文本纠错**: 展示单次 AI 调用、性能监控
- **知识问答**: 展示 RAG 查询、知识库选择

---

## 📖 迁移指南

### 从 v1 迁移到 v2

#### v1 代码（旧架构）

```javascript
class MyPlugin extends ChatPlugin {
    constructor() {
        super();
        this.name = 'MyPlugin';
    }

    async onInit(context) {
        await super.onInit(context);
        this.setupUI();
    }

    setupUI() {
        this.setHTML(`<div>...</div>`);
        this.addStyles(`...`);
    }

    async onRun(userInput) {
        await this.sendMessage(userInput);
    }
}

window.runPlugin = async function(userInput) {
    // 复杂的初始化逻辑...
};
```

#### v2 代码（新架构）

```html
<!DOCTYPE html>
<html>
<head>
    <style>/* 样式 */</style>
</head>
<body>
    <div>...</div>

    <script>
        SquirrelBridge.onInit((context) => {
            console.log('Initialized');
        });

        SquirrelBridge.onInput((text) => {
            sendMessage(text);
        });

        async function sendMessage(text) {
            await SquirrelBridge.AI.streamChat({
                prompt: text,
                onChunk: (chunk) => { /* ... */ }
            });
        }
    </script>
</body>
</html>
```

**代码量减少 70%+！**

---

## ❓ 常见问题

### Q: 如何调试插件？

A: 开发模式下，直接在浏览器中打开 `index.html`，所有 API 都会使用 Mock 数据。

### Q: TypeScript 如何配置？

A: 在项目根目录添加 `tsconfig.json`，引用 SDK 的类型定义文件。

### Q: 如何处理大量数据？

A: 使用 Stream API 进行流式传输，避免一次性加载所有数据。

### Q: 性能如何优化？

A: 使用内置的 Performance API 监控瓶颈，参考最佳实践进行优化。

---

## 📞 反馈与支持

- GitHub Issues: [提交问题](https://github.com/...)
- 文档: [完整文档](https://docs...)
- 示例: [示例插件库](https://github.com/...)

---

**Squirrel Bridge v2.0 - 让插件开发更简单！**
