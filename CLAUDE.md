# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Squirrel (鼠鬚管)** is an AI-enhanced macOS input method application built on the Rime Input Method Engine. This fork extends the original Squirrel with comprehensive AI integration capabilities, including LLM-powered plugins, RAG (Retrieval-Augmented Generation), and external agent support.

## Build Commands

### Basic Build
```bash
# Build release version (most common)
make release

# Build debug version
make debug

# Install release version to /Library/Input Methods
make install
# or
make install-release

# Install debug version
make install-debug
```

### Dependency Management
```bash
# Build all dependencies (librime + data)
make deps

# Build only librime
make librime

# Build only data files (plum + opencc)
make data
```

### Xcode Build
```bash
# Direct xcodebuild (after dependencies are ready)
xcodebuild -project Squirrel.xcodeproj -configuration Release -scheme Squirrel -derivedDataPath build build
```

### Clean
```bash
# Clean build artifacts
make clean

# Clean package files
make clean-package

# Clean all dependencies (librime, plum, sparkle)
make clean-deps
```

## Architecture Overview

### Core Components

1. **Rime Integration Layer** (`sources/`)
   - `SquirrelInputController.swift`: Main IMK input controller, handles keystroke processing
   - `SquirrelApplicationDelegate.swift`: Application lifecycle, global hotkey management (Cmd+Shift+Space)
   - `SquirrelPanel.swift`: Candidate window UI
   - `BridgingFunctions.swift`: Swift-C bridging for librime API

2. **AI Plugin System** (`sources/AIPlugins/`)
   - **Bridge API v2** (`resources/AIPlugins/sdk_v2/`): Modern HTML/JS plugin architecture
   - **Models**: Plugin metadata, AI provider configurations, conversation sessions
   - **Services**:
     - `JSBridge.swift`: JavaScript execution context for plugins
     - `AIAPIService.swift`: LLM API integration (OpenAI-compatible)
     - `DynamicPluginManager.swift`: Plugin lifecycle management
     - `KnowledgeBaseService.swift`: RAG implementation with SQLite vector storage
     - `MCPBridgeHandler.swift`: Model Context Protocol support
     - `AgentBridgeHandler.swift`: External agent invocation

3. **Input Statistics** (`sources/InputStatsManager.swift`)
   - Tracks user typing patterns and space-triggered commits
   - Used for analytics and AI context

4. **librime** (`librime/` submodule)
   - Core input method engine written in C++
   - Schema-based architecture for different input methods
   - Build target: `librime/dist/lib/librime.1.dylib`

### Key Architectural Patterns

**Plugin Architecture**:
- v1 (Legacy): Class-based plugins inheriting from base classes
- v2 (Current): Single HTML file with standard Bridge API
- Plugins run in isolated WebView contexts with JSContext for JS execution
- Communication via `SquirrelBridge` JavaScript API exposed to plugins

**Rime Session Management**:
- Each IMKTextInput client gets a Rime session (RimeSessionId)
- Sessions track composition state, candidates, and schema configuration
- `SquirrelInputController` manages session lifecycle and updates

**AI Integration Flow**:
1. User triggers plugin via Cmd+Shift+Space
2. `AIPluginWindowManager` creates/shows window
3. Plugin loads in WebView with JSBridge
4. Plugin calls `SquirrelBridge.AI.chat()` or `.streamChat()`
5. JSBridge forwards to `AIAPIService`
6. Response streams back through callbacks

**Context Insertion Feature** (Command+I):
- `SquirrelInputController` intercepts Cmd+I
- Reads up to 3 lines of text above cursor via IMKTextInput protocol
- Inserts formatted context: `[App: AppName]\n{context_text}`
- Useful for providing context to AI plugins

## Important File Locations

- **Main app sources**: `sources/`
- **AI plugin SDK**: `resources/AIPlugins/sdk_v2/`
- **Example plugins**: `resources/AIPlugins/modern_chat_v2/`
- **Rime data**: `data/plum/` (schemas), `data/opencc/` (Chinese conversion)
- **Build output**: `build/Build/Products/Release/Squirrel.app`
- **Xcode project**: `Squirrel.xcodeproj/`

## Development Workflow

### Making Changes to Swift Code
1. Edit files in `sources/` or `sources/AIPlugins/`
2. Run `make debug` or `make release`
3. Run `make install-debug` or `make install-release`
4. Log out and log back in (or use `DSTROOT="/Library/Input Methods" bash scripts/postinstall`)

### Updating librime
The librime submodule is built separately. To update:
```bash
cd librime
git pull
cd ..
make librime
```

### Developing Plugins
Plugin entry point is defined in `config.json`:
```json
{
  "id": "com.example.plugin",
  "name": "My Plugin",
  "entry": "index.html",
  "capabilities": {
    "ai": ["chat", "stream"],
    "storage": ["local"]
  }
}
```

Plugins use Bridge API v2 (see `resources/AIPlugins/sdk_v2/README.md` for full documentation):
- `SquirrelBridge.AI.chat()` - Single AI completion
- `SquirrelBridge.AI.streamChat()` - Streaming AI response
- `SquirrelBridge.Storage.get/set()` - Local storage
- `SquirrelBridge.RAG.query()` - Knowledge base search

### Testing
There is no automated test suite. Testing is done manually:
1. Build and install
2. Switch to Squirrel input method
3. Test input in various applications
4. Test AI plugins via Cmd+Shift+Space

## Key Dependencies

- **Sparkle**: Auto-update framework (`Sparkle/` submodule)
- **librime**: Input method engine (`librime/` submodule)
- **plum**: Rime schema package manager (`plum/` submodule)
- **OpenCC**: Traditional/Simplified Chinese conversion (built as part of librime)

## Build Settings

- **Target**: macOS 13.0+
- **Swift**: Latest version supported by Xcode
- **Architectures**: Set via `ARCHS` environment variable (e.g., `ARCHS="x86_64 arm64"`)
- **Deployment target**: Set via `MACOSX_DEPLOYMENT_TARGET`

## Special Considerations

1. **Global Hotkeys**: The app uses Carbon Event Manager (legacy API) to register Cmd+Shift+Space without requiring Accessibility permissions.

2. **Input Method Kit**: Uses Apple's IMK framework. Key methods:
   - `handle(_:client:)` - Process keystrokes
   - `activateServer(_:)` - Input method activated
   - `commitComposition(_:)` - Finalize input

3. **Rime API**: All C API calls go through `rimeAPI: RimeApi_stdbool`
   - `create_session()` - Start new input session
   - `process_key()` - Process keystroke
   - `get_context()` - Get candidates and preedit
   - `get_commit()` - Get finalized text

4. **JSBridge Sync/Async**: JSBridge supports both sync (`callAISync`) and async (`callAIStream`) AI calls to avoid blocking JavaScript execution.

5. **Permission Model**: Plugins declare required capabilities in `config.json`. The system enforces these at runtime.

## Common Issues

- **Input method not showing up**: Log out and log back in after installation
- **Candidates not displaying**: Check `SquirrelPanel` initialization and theme configuration
- **AI plugins not loading**: Check plugin `config.json` syntax and ensure entry file exists
- **Build failures**: Ensure all dependencies are built (`make deps`) before building main app

## Package and Distribution

```bash
# Create installer package
make package

# Create signed archive for updates (requires DEV_ID)
DEV_ID="Developer Name" make archive
```

The package is code-signed and notarized for distribution via Sparkle updates.
