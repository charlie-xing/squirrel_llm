# Agent & MCP 功能手工测试指南

## 📋 测试准备

### 编译状态
✅ **编译成功** - Exit Code: 0

### 测试文件位置
- 测试工具: `/Users/xcl/rime/squirrel_llm/resources/AIPlugins/agent_test.html`
- SDK 文件: `/Users/xcl/rime/squirrel_llm/resources/AIPlugins/sdk_v2/squirrel-bridge.js`
- 类型定义: `/Users/xcl/rime/squirrel_llm/resources/AIPlugins/sdk_v2/squirrel-bridge.d.ts`

---

## 🧪 方案一：浏览器 Mock API 测试（推荐优先测试）

这个方案使用开发模式的 Mock API，可以快速验证所有 API 接口的完整性和正确性。

### 步骤 1：打开测试工具

```bash
# 在浏览器中打开测试 HTML
open /Users/xcl/rime/squirrel_llm/resources/AIPlugins/agent_test.html

# 或者使用 Safari
open -a Safari /Users/xcl/rime/squirrel_llm/resources/AIPlugins/agent_test.html
```

### 步骤 2：打开浏览器开发者工具

1. 按 `Cmd + Option + I` 打开开发者工具
2. 切换到 **Console** 标签页
3. 观察日志输出

### 步骤 3：测试 Agent API

#### 3.1 注册 Agent
1. 点击 **"注册测试 Agent"** 按钮
2. **预期结果**:
   ```
   ✅ Agent 注册成功!

   Agent ID: test-agent-1
   Name: 测试 Agent
   Endpoint: http://localhost:8000/agent
   Auth Type: bearer
   Capabilities: chat, analyze, summarize
   ```
3. **验证点**:
   - 界面显示成功消息
   - Console 没有错误
   - Agent 配置正确显示

#### 3.2 列出 Agents
1. 点击 **"获取 Agent 列表"** 按钮
2. **预期结果**:
   ```
   ✅ 找到 2 个 Agent:

   1. Mock Agent (mock-agent-1)
      Endpoint: http://localhost:3000
      Capabilities: chat, search

   2. 测试 Agent (test-agent-1)
      Endpoint: http://localhost:8000/agent
      Capabilities: chat, analyze, summarize
   ```
3. **验证点**:
   - 显示至少 2 个 Agent（1 个 Mock + 1 个刚注册的）
   - Agent 信息完整

#### 3.3 调用 Agent（普通）
1. 点击 **"调用 Agent"** 按钮
2. **预期结果**:
   ```
   ✅ Agent 调用成功!

   Success: true
   Data: {
     "result": "Mock agent response for analyze"
   }
   Metadata: {
     "executionTime": 300
   }

   ⏱️ 性能: 300.xx ms
   ```
3. **验证点**:
   - 调用成功
   - 返回数据正确
   - 性能时间 < 500ms

#### 3.4 流式调用 Agent
1. 点击 **"开始流式调用"** 按钮
2. **预期结果**:
   ```
   🔄 开始流式调用...

   Chunk 1: chunk1
   Chunk 2: chunk2
   Chunk 3: chunk3

   ✅ 流式调用完成!
   总共收到 3 个数据块
   Final data: {
     "final": "completed"
   }
   ```
3. **验证点**:
   - 按钮在调用期间禁用
   - 实时显示数据块
   - 完成后按钮恢复
   - 接收到所有 3 个数据块

### 步骤 4：测试 MCP API

#### 4.1 获取 MCP 上下文
1. 点击 **"获取上下文"** 按钮
2. **预期结果**:
   ```
   ✅ MCP 上下文获取成功!

   Resources: 1
   Tools: 1
   Prompts: 1

   Server Info:
     Name: Mock MCP Server
     Version: 1.0.0
     Protocol: 2024-11-05
   ```
3. **验证点**:
   - 正确返回资源、工具、提示词数量
   - 服务器信息完整

#### 4.2 列出 MCP 工具
1. 点击 **"列出工具"** 按钮
2. **预期结果**:
   ```
   ✅ 找到 1 个工具:

   1. mock_tool
      Description: A mock MCP tool
      Schema: {
        "type": "object",
        "properties": {
          "query": {
            "type": "string"
          }
        }
      }
   ```
3. **验证点**:
   - 工具信息完整
   - Schema 正确显示

#### 4.3 使用 MCP 工具
1. 点击 **"调用工具"** 按钮
2. **预期结果**:
   ```
   ✅ 工具调用成功!

   Success: true
   Content:
     1. Type: text
        Text: Mock tool result for mock_tool with params: {"query":"测试查询"}

   ⏱️ 性能: 200.xx ms
   ```
3. **验证点**:
   - 工具调用成功
   - 返回正确的文本内容
   - 性能 < 300ms

#### 4.4 获取 MCP 资源
1. 点击 **"获取资源"** 按钮
2. **预期结果**:
   ```
   ✅ 资源获取成功!

   URI: file:///mock/document.txt
   MIME Type: text/plain
   Content:
   Mock resource content
   ```
3. **验证点**:
   - 资源正确获取
   - MIME 类型正确
   - 内容显示

#### 4.5 获取提示词
1. 点击 **"获取提示词"** 按钮
2. **预期结果**:
   ```
   ✅ 提示词获取成功!

   Description: Mock prompt

   Messages:
   1. Role: user
      Content: Mock prompt for mock_prompt with args: {"topic":"AI 技术"}
   ```
3. **验证点**:
   - 提示词正确返回
   - 参数正确传递

### 步骤 5：测试性能监控

1. 点击 **"测试性能监控"** 按钮
2. **预期结果**:
   ```
   ✅ 性能监控测试完成!

   总耗时: 600.xx ms

   所有性能记录:
     test.start: 0ms
     agents.done: 200ms
     tools.done: 400ms
     test.end: 600ms
   ```
3. **验证点**:
   - 所有操作完成
   - 性能记录正确
   - 总时间合理

### 步骤 6：检查 Console 日志

在浏览器 Console 中应该看到类似的日志：

```
[Bridge] Squirrel Bridge SDK v2.0.0 loaded
[Test] Mock API enabled
[Test] Agent & MCP Test Tool loaded
[Test] SquirrelBridge version: Object { ... }
[Test] Registering agent...
[Test] Listing agents...
[Mock Agent] Invoked with params: {...}
[Bridge Performance] Slow call: agent.invoke took 300.00ms
```

---

## 🚀 方案二：集成测试（需要先完成 Phase 2）

⚠️ **注意**: 此方案需要先完成 PluginViewModel 的集成工作（Phase 2）才能测试。

### 前置条件

需要完成以下工作（参考 `BRIDGE_V2_ROADMAP.md` Phase 2）:

1. 修改 `PluginViewModel.swift` 支持 v2 插件
2. 实现插件版本检测（`isV2Plugin`）
3. 注册 SquirrelBridge 到 WebView
4. 设置流式事件处理器

### 集成测试步骤

#### 1. 创建测试用的 Agent 服务器

```bash
# 可以使用 Python 快速创建一个测试服务器
cat > /tmp/test_agent.py << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class AgentHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)
        data = json.loads(body)

        response = {
            "success": True,
            "data": {
                "result": f"Agent response for action: {data.get('action')}",
                "params": data.get('params')
            },
            "metadata": {
                "timestamp": "2025-10-12T12:00:00Z"
            }
        }

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

print("Starting test agent server on http://localhost:8000")
HTTPServer(('localhost', 8000), AgentHandler).serve_forever()
EOF

# 运行服务器
python3 /tmp/test_agent.py
```

#### 2. 在 Squirrel 应用中测试

1. **启动应用**:
   ```bash
   open /Users/xcl/rime/squirrel_llm/build/Build/Products/Release/Squirrel.app
   ```

2. **打开插件页面** (使用「现代聊天 v2」或自定义测试插件)

3. **在插件中注册 Agent**:
   ```javascript
   await SquirrelBridge.Agent.registerAgent({
       id: 'local-test-agent',
       name: 'Local Test Agent',
       endpoint: 'http://localhost:8000',
       auth: { type: 'bearer', token: 'test' }
   });
   ```

4. **调用 Agent**:
   ```javascript
   const response = await SquirrelBridge.Agent.invoke({
       agent: 'local-test-agent',
       action: 'test',
       params: { message: 'Hello' }
   });
   console.log(response);
   ```

#### 3. 检查日志

查看应用日志：
```bash
log stream --predicate 'process == "Squirrel"' --level debug | grep -i "agent\|bridge"
```

预期看到：
```
[AgentBridge] Registered agent: Local Test Agent (local-test-agent)
[Bridge] Handling: agent.invoke
[AgentBridge] Invoking agent: local-test-agent
[Bridge] ⏱️ agent.invoke completed in 123ms
```

---

## ✅ 测试检查清单

### Agent API
- [ ] 注册 Agent 成功
- [ ] 列出 Agents 包含所有已注册的
- [ ] 普通调用返回正确数据
- [ ] 流式调用实时接收数据
- [ ] 取消注册 Agent 成功
- [ ] 获取特定 Agent 配置成功

### MCP API
- [ ] 获取 MCP 上下文成功
- [ ] 列出工具返回完整列表
- [ ] 使用工具返回正确结果
- [ ] 获取资源成功
- [ ] 获取提示词成功
- [ ] 订阅/取消订阅资源成功

### 性能
- [ ] Agent 调用 < 500ms
- [ ] MCP 工具调用 < 300ms
- [ ] 性能监控正确记录
- [ ] 超过阈值有警告日志

### 错误处理
- [ ] 错误请求返回错误信息
- [ ] 超时正确处理
- [ ] 网络错误正确捕获

---

## 🐛 常见问题排查

### 问题 1: 浏览器打开测试页面显示空白

**解决方法**:
1. 检查 Console 是否有 JavaScript 错误
2. 确认 `sdk_v2/squirrel-bridge.js` 文件存在
3. 尝试刷新页面（Cmd + R）

### 问题 2: Mock API 不返回数据

**解决方法**:
1. 检查 Console 日志中是否有 `[Test] Mock API enabled`
2. 确认 `window.SquirrelBridge.isDevelopment = true` 已设置
3. 检查 `squirrel-bridge.js` 的开发模式代码

### 问题 3: 集成测试时 Agent 调用失败

**解决方法**:
1. 确认测试服务器正在运行（`curl http://localhost:8000`）
2. 检查网络权限（entitlements 中的 `com.apple.security.network.client`）
3. 查看应用日志中的错误信息

### 问题 4: 性能监控显示异常

**解决方法**:
1. 确认 `Performance.mark()` 在操作前后都被调用
2. 检查 mark 名称是否正确
3. 确认使用了正确的 start/end mark 名称

---

## 📊 测试报告模板

测试完成后，可以使用此模板记录结果：

```markdown
# Agent & MCP 功能测试报告

**测试日期**: 2025-10-12
**测试环境**: macOS, Safari/Chrome
**测试方案**: 浏览器 Mock API 测试

## Agent API 测试结果

| 功能 | 状态 | 备注 |
|------|------|------|
| 注册 Agent | ✅/❌ | |
| 列出 Agents | ✅/❌ | |
| 普通调用 | ✅/❌ | 耗时: XXms |
| 流式调用 | ✅/❌ | 接收数据块: X 个 |
| 取消注册 | ✅/❌ | |
| 获取配置 | ✅/❌ | |

## MCP API 测试结果

| 功能 | 状态 | 备注 |
|------|------|------|
| 获取上下文 | ✅/❌ | |
| 列出工具 | ✅/❌ | |
| 使用工具 | ✅/❌ | 耗时: XXms |
| 获取资源 | ✅/❌ | |
| 获取提示词 | ✅/❌ | |

## 发现的问题

1. [问题描述]
2. [问题描述]

## 建议改进

1. [建议]
2. [建议]
```

---

## 🎯 下一步

测试完成后：

1. **如果 Mock API 测试通过**:
   - 可以开始 Phase 2 集成工作
   - 参考 `BRIDGE_V2_ROADMAP.md` 的实施步骤

2. **如果发现问题**:
   - 记录具体错误信息
   - 检查 Console 日志
   - 查看相关代码文件

3. **准备集成测试**:
   - 搭建真实的 Agent 服务器
   - 配置 MCP 服务器（可选）
   - 准备测试数据

---

**测试文档版本**: 1.0
**最后更新**: 2025-10-12
