import SwiftUI

/// Pure SwiftUI multi-line expandable text input with toolbar
struct ExpandableTextInput: View {
    @Binding var text: String
    @Binding var selectedKnowledgeBase: KnowledgeBase?
    @FocusState private var isFocused: Bool
    @State private var showingKnowledgeBaseSelection = false
    @State private var textEditorHeight: CGFloat = 44  // Start at 2 lines
    @ObservedObject private var knowledgeBaseManager = KnowledgeBaseManager()

    let placeholder: String
    let onSend: () -> Void

    private let lineHeight: CGFloat = 22
    private let minHeight: CGFloat = 44   // 2 lines
    private let maxHeight: CGFloat = 110  // 5 lines

    var body: some View {
        VStack(spacing: 0) {
            // Text editor area
            ZStack(alignment: .topLeading) {
                // Placeholder
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                // TextEditor with dynamic height
                GeometryReader { geometry in
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .onChange(of: text) { newValue in
                            updateHeight(for: newValue, width: geometry.size.width)
                        }
                        .onAppear {
                            // Auto-focus on appear
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isFocused = true
                            }
                        }
                }
                .frame(height: textEditorHeight)

                // Invisible overlay to capture Command+Enter
                Color.clear
                    .contentShape(Rectangle())
                    .onKeyPress(.return, modifiers: .command) { keyPress in
                        handleSubmit()
                        return .handled
                    }
            }
            .frame(height: textEditorHeight)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Toolbar
            HStack(spacing: 12) {
                // Left side buttons
                HStack(spacing: 8) {
                    ToolbarButton(icon: "paperclip", tooltip: "Add attachment") {
                        // TODO: Implement attachment
                    }

                    ToolbarButton(
                        icon: selectedKnowledgeBase != nil
                            ? "books.vertical.fill" : "books.vertical",
                        tooltip: selectedKnowledgeBase?.name ?? "Select knowledge base",
                        isSelected: selectedKnowledgeBase != nil
                    ) {
                        showingKnowledgeBaseSelection.toggle()
                    }
                    .popover(isPresented: $showingKnowledgeBaseSelection) {
                        KnowledgeBaseSelectionView(
                            knowledgeBases: knowledgeBaseManager.knowledgeBases.filter {
                                $0.displayStatus == .ready
                            },
                            selectedKnowledgeBase: $selectedKnowledgeBase,
                            onDismiss: {
                                showingKnowledgeBaseSelection = false
                            }
                        )
                    }

                    ToolbarButton(icon: "globe", tooltip: "Web search") {
                        // TODO: Implement web search
                    }

                    ToolbarButton(icon: "magnifyingglass.circle", tooltip: "Deep research") {
                        // TODO: Implement deep research
                    }
                }

                Spacer()

                // Run button
                Button(action: {
                    print("ExpandableTextInput: Run button clicked, text: '\(text)'")
                    handleSubmit()
                }) {
                    HStack(spacing: 4) {
                        Text("Run")
                            .font(.system(size: 13, weight: .medium))
                        Text("⌘↵")
                            .font(.system(size: 11))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(text.isEmpty ? Color.gray : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func handleSubmit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("ExpandableTextInput: Submit ignored - empty text")
            return
        }
        print("ExpandableTextInput: Submitting text: '\(trimmed)'")
        onSend()
    }

    private func updateHeight(for text: String, width: CGFloat) {
        // Calculate the required height based on text content
        let font = NSFont.systemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Use NSString to calculate bounding rect
        let textStorage = NSTextStorage(string: text.isEmpty ? "M" : text, attributes: attributes)
        let textContainer = NSTextContainer(size: NSSize(width: width - 24, height: .greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        textContainer.lineFragmentPadding = 0
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let calculatedHeight = usedRect.height + 24  // Add padding

        // Clamp between min and max height
        let newHeight = max(minHeight, min(calculatedHeight, maxHeight))

        if abs(newHeight - textEditorHeight) > 1 {
            withAnimation(.easeInOut(duration: 0.1)) {
                textEditorHeight = newHeight
            }
        }
    }
}

/// Toolbar button component
struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    let isSelected: Bool
    let action: () -> Void

    init(icon: String, tooltip: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.tooltip = tooltip
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.2)
                                : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

/// Knowledge Base Selection View
struct KnowledgeBaseSelectionView: View {
    let knowledgeBases: [KnowledgeBase]
    @Binding var selectedKnowledgeBase: KnowledgeBase?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Knowledge Base")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .opacity(0.7)
                .scaleEffect(0.9)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        // Add subtle hover animation
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()
                .opacity(0.3)

            // Knowledge Base List
            if knowledgeBases.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.tertiary.opacity(0.3))
                            .frame(width: 48, height: 48)

                        Image(systemName: "books.vertical")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                    }

                    VStack(spacing: 4) {
                        Text("No Knowledge Bases")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Text("Create one in Settings to get started")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .opacity(0.85)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // None option
                        KnowledgeBaseSelectionRow(
                            knowledgeBase: nil,
                            isSelected: selectedKnowledgeBase == nil,
                            onSelect: {
                                selectedKnowledgeBase = nil
                                onDismiss()
                            }
                        )

                        Divider()
                            .padding(.leading, 36)
                            .opacity(0.3)

                        // Knowledge bases
                        ForEach(knowledgeBases) { kb in
                            KnowledgeBaseSelectionRow(
                                knowledgeBase: kb,
                                isSelected: selectedKnowledgeBase?.id == kb.id,
                                onSelect: {
                                    selectedKnowledgeBase = kb
                                    onDismiss()
                                }
                            )

                            if kb.id != knowledgeBases.last?.id {
                                Divider()
                                    .padding(.leading, 36)
                                    .opacity(0.3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial, style: FillStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
                .blendMode(.overlay)
        )
    }
}

/// Knowledge Base Selection Row
struct KnowledgeBaseSelectionRow: View {
    let knowledgeBase: KnowledgeBase?
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon with subtle background
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            knowledgeBase != nil
                                ? LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.15),
                                        Color.accentColor.opacity(0.05),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.08),
                                        Color.secondary.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
                        )

                    Image(systemName: knowledgeBase?.type.icon ?? "xmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(knowledgeBase != nil ? .accentColor : .secondary)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(knowledgeBase?.name ?? "None")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let kb = knowledgeBase {
                        Text("\(kb.totalDocuments) documents • \(kb.totalChunks) chunks")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .opacity(0.85)
                    } else {
                        Text("No knowledge base selected")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .opacity(0.85)
                    }
                }

                Spacer()

                // Selection indicator with animation
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .scaleEffect(isSelected ? 1.0 : 0.1)

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(isSelected ? 1.0 : 0.1)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : (isHovered
                            ? LinearGradient(
                                colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    isSelected
                        ? RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                        : nil
                )
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
