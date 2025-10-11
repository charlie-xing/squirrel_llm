//
//  SquirrelInputController.swift
//  Squirrel
//
//  Created by Leo Liu on 5/7/24.
//

import InputMethodKit

final class SquirrelInputController: IMKInputController {
    private static let keyRollOver = 50
    private static var unknownAppCnt: UInt = 0

    private weak var client: IMKTextInput?
    private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
    private var preedit: String = ""
    private var selRange: NSRange = .empty
    private var caretPos: Int = 0
    private var lastModifiers: NSEvent.ModifierFlags = .init()
    private var session: RimeSessionId = 0
    private var schemaId: String = ""
    private var inlinePreedit = false
    private var inlineCandidate = false
    // for chord-typing
    private var chordKeyCodes: [UInt32] = .init(
        repeating: 0, count: SquirrelInputController.keyRollOver)
    private var chordModifiers: [UInt32] = .init(
        repeating: 0, count: SquirrelInputController.keyRollOver)
    private var chordKeyCount: Int = 0
    private var chordTimer: Timer?
    private var chordDuration: TimeInterval = 0
    private var currentApp: String = ""

    // 异步处理器
    private var asyncProcessor: AsyncRimeProcessor?

    // swiftlint:disable:next cyclomatic_complexity
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        let modifiers = event.modifierFlags
        let changes = lastModifiers.symmetricDifference(modifiers)

        // Return true to indicate the the key input was received and dealt with.
        // Key processing will not continue in that case.  In other words the
        // system will not deliver a key down event to the application.
        // Returning false means the original key down will be passed on to the client.
        var handled = false

        if session == 0 || !rimeAPI.find_session(session) {
            createSession()
            if session == 0 {
                return false
            }
        }

        self.client ?= sender as? IMKTextInput
        if let app = client?.bundleIdentifier(), currentApp != app {
            currentApp = app
            updateAppOptions()
        }

        switch event.type {
        case .flagsChanged:
            if lastModifiers == modifiers {
                handled = true
                break
            }
            // print("[DEBUG] FLAGSCHANGED client: \(sender ?? "nil"), modifiers: \(modifiers)")
            var rimeModifiers: UInt32 = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
            // For flags-changed event, keyCode is available since macOS 10.15
            // (#715)
            let rimeKeycode: UInt32 = SquirrelKeycode.osxKeycodeToRime(
                keycode: event.keyCode, keychar: nil, shift: false, caps: false)

            if changes.contains(.capsLock) {
                // NOTE: rime assumes XK_Caps_Lock to be sent before modifier changes,
                // while NSFlagsChanged event has the flag changed already.
                // so it is necessary to revert kLockMask.
                rimeModifiers ^= kLockMask.rawValue
                _ = processKey(rimeKeycode, modifiers: rimeModifiers)
            }

            // Need to process release before modifier down. Because
            // sometimes release event is delayed to next modifier keydown.
            var buffer = [(keycode: UInt32, modifier: UInt32)]()
            for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command]
            where changes.contains(flag) {
                if modifiers.contains(flag) {  // New modifier
                    buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
                } else {  // Release
                    buffer.insert(
                        (keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue),
                        at: 0)
                }
            }
            for (keycode, modifier) in buffer {
                _ = processKey(keycode, modifiers: modifier)
            }

            lastModifiers = modifiers
            rimeUpdate()

        case .keyDown:
            // Handle Command+I for context insertion
            if modifiers.contains(.command) && event.keyCode == kVK_ANSI_I {
                handled = handleContextInsertionShortcut()
                break
            }

            // ignore other Command+X hotkeys.
            if modifiers.contains(.command) {
                break
            }

            let keyCode = event.keyCode
            var keyChars = event.charactersIgnoringModifiers
            let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
            if let code = keyChars?.first,
                (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII)
            {
                keyChars = event.characters
            }
            // print("[DEBUG] KEYDOWN client: \(sender ?? "nil"), modifiers: \(modifiers), keyCode: \(keyCode), keyChars: [\(keyChars ?? "empty")]")

            // translate osx keyevents to rime keyevents
            if let char = keyChars?.first {
                let rimeKeycode = SquirrelKeycode.osxKeycodeToRime(
                    keycode: keyCode, keychar: char,
                    shift: modifiers.contains(.shift),
                    caps: modifiers.contains(.capsLock))
                if rimeKeycode != 0 {
                    let rimeModifiers = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
                    handled = processKey(rimeKeycode, modifiers: rimeModifiers)
                    rimeUpdate()
                }
            }

        default:
            break
        }

        return handled
    }

    func selectCandidate(_ index: Int) -> Bool {
        if let processor = asyncProcessor {
            processor.selectCandidateAsync(index)
            return true
        } else {
            // 回退到同步模式
            let success = rimeAPI.select_candidate_on_current_page(session, index)
            if success {
                rimeUpdate()
            }
            return success
        }
    }

    // swiftlint:disable:next identifier_name
    func page(up: Bool) -> Bool {
        if let processor = asyncProcessor {
            processor.changePageAsync(up: up)
            return true
        } else {
            // 回退到同步模式
            var handled = false
            handled = rimeAPI.change_page(session, up)
            if handled {
                rimeUpdate()
            }
            return handled
        }
    }

    func moveCaret(forward: Bool) -> Bool {
        if let processor = asyncProcessor {
            let currentCaretPos = processor.getCaretPos()
            guard let input = processor.getInput() else { return false }
            let newCaretPos: Int
            if forward {
                if currentCaretPos <= 0 {
                    return false
                }
                newCaretPos = currentCaretPos - 1
            } else {
                if currentCaretPos >= input.utf8.count {
                    return false
                }
                newCaretPos = currentCaretPos + 1
            }
            processor.setCaretPosAsync(newCaretPos)
            return true
        } else {
            // 回退到同步模式
            let currentCaretPos = rimeAPI.get_caret_pos(session)
            guard let input = rimeAPI.get_input(session) else { return false }
            if forward {
                if currentCaretPos <= 0 {
                    return false
                }
                rimeAPI.set_caret_pos(session, currentCaretPos - 1)
            } else {
                let inputStr = String(cString: input)
                if currentCaretPos >= inputStr.utf8.count {
                    return false
                }
                rimeAPI.set_caret_pos(session, currentCaretPos + 1)
            }
            rimeUpdate()
            return true
        }
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        // print("[DEBUG] recognizedEvents:")
        return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        self.client ?= sender as? IMKTextInput
        // print("[DEBUG] activateServer:")
        var keyboardLayout = NSApp.squirrelAppDelegate.config?.getString("keyboard_layout") ?? ""
        if keyboardLayout == "last" || keyboardLayout == "" {
            keyboardLayout = ""
        } else if keyboardLayout == "default" {
            keyboardLayout = "com.apple.keylayout.ABC"
        } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
            keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
        }
        if keyboardLayout != "" {
            client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
        }
        preedit = ""
    }

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        self.client = client as? IMKTextInput
        // print("[DEBUG] initWithServer: \(server ?? .init()) delegate: \(delegate ?? "nil") client:\(client ?? "nil")")
        super.init(server: server, delegate: delegate, client: client)
        createSession()
    }

    override func deactivateServer(_ sender: Any!) {
        // print("[DEBUG] deactivateServer: \(sender ?? "nil")")
        hidePalettes()
        commitComposition(sender)
        client = nil
    }

    override func hidePalettes() {
        NSApp.squirrelAppDelegate.panel?.hide()
        super.hidePalettes()
    }

    /*!
     @method
     @abstract   Called when a user action was taken that ends an input session.
     Typically triggered by the user selecting a new input method
     or keyboard layout.
     @discussion When this method is called your controller should send the
     current input buffer to the client via a call to
     insertText:replacementRange:.  Additionally, this is the time
     to clean up if that is necessary.
     */
    override func commitComposition(_ sender: Any!) {
        self.client ?= sender as? IMKTextInput
        // print("[DEBUG] commitComposition: \(sender ?? "nil")")
        //  commit raw input
        if session != 0 {
            if let processor = asyncProcessor {
                if let input = processor.getInput() {
                    commit(string: input)
                    processor.clearComposition()
                }
            } else {
                if let input = rimeAPI.get_input(session) {
                    commit(string: String(cString: input))
                    rimeAPI.clear_composition(session)
                }
            }
        }
    }

    override func menu() -> NSMenu! {
        let deploy = NSMenuItem(
            title: NSLocalizedString("Deploy", comment: "Menu item"), action: #selector(deploy),
            keyEquivalent: "`")
        deploy.target = self
        deploy.keyEquivalentModifierMask = [.control, .option]
        let sync = NSMenuItem(
            title: NSLocalizedString("Sync user data", comment: "Menu item"),
            action: #selector(syncUserData), keyEquivalent: "")
        sync.target = self
        let logDir = NSMenuItem(
            title: NSLocalizedString("Logs...", comment: "Menu item"),
            action: #selector(openLogFolder), keyEquivalent: "")
        logDir.target = self
        let setting = NSMenuItem(
            title: NSLocalizedString("Settings...", comment: "Menu item"),
            action: #selector(openRimeFolder), keyEquivalent: "")
        setting.target = self
        let wiki = NSMenuItem(
            title: NSLocalizedString("Rime Wiki...", comment: "Menu item"),
            action: #selector(openWiki), keyEquivalent: "")
        wiki.target = self
        let update = NSMenuItem(
            title: NSLocalizedString("Check for updates...", comment: "Menu item"),
            action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self

        let menu = NSMenu()
        menu.addItem(deploy)
        menu.addItem(sync)
        menu.addItem(logDir)
        menu.addItem(setting)
        menu.addItem(wiki)
        menu.addItem(update)

        return menu
    }

    @objc func deploy() {
        NSApp.squirrelAppDelegate.deploy()
    }

    @objc func syncUserData() {
        NSApp.squirrelAppDelegate.syncUserData()
    }

    @objc func openLogFolder() {
        NSApp.squirrelAppDelegate.openLogFolder()
    }

    @objc func openRimeFolder() {
        NSApp.squirrelAppDelegate.openRimeFolder()
    }

    @objc func checkForUpdates() {
        NSApp.squirrelAppDelegate.checkForUpdates()
    }

    @objc func openWiki() {
        NSApp.squirrelAppDelegate.openWiki()
    }

    deinit {
        destroySession()
    }

    // MARK: - Public Methods for Panel
    func getCurrentCandidates() -> [String] {
        guard session != 0 else { return [] }

        var ctx = RimeContext_stdbool.rimeStructInit()
        guard rimeAPI.get_context(session, &ctx) else {
            return []
        }

        let numCandidates = Int(ctx.menu.num_candidates)
        var candidates = [String]()
        for i in 0..<numCandidates {
            let candidate = ctx.menu.candidates[i]
            candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        }

        rimeAPI.free_context(&ctx)
        return candidates
    }
}

// MARK: - AsyncRimeProcessorDelegate
extension SquirrelInputController: AsyncRimeProcessorDelegate {
    func onRimeStateUpdated(hasInput: Bool) {
        // 在主线程更新UI，传递输入状态
        rimeUpdate(forceShowPanel: hasInput)
    }

    func onRimeCommitText(_ text: String) {
        // 在主线程提交文本
        commit(string: text)
    }
}

extension SquirrelInputController {

    fileprivate func onChordTimer(_: Timer) {
        // chord release triggered by timer
        var processedKeys = false
        if chordKeyCount > 0 && session != 0 {
            // simulate key-ups
            for i in 0..<chordKeyCount {
                let handled = rimeAPI.process_key(
                    session, Int32(chordKeyCodes[i]),
                    Int32(chordModifiers[i] | kReleaseMask.rawValue))
                if handled {
                    processedKeys = true
                }
            }
        }
        clearChord()
        if processedKeys {
            rimeUpdate()
        }
    }

    fileprivate func updateChord(keycode: UInt32, modifiers: UInt32) {
        // print("[DEBUG] update chord: {\(chordKeyCodes)} << \(keycode)")
        for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
            return
        }
        if chordKeyCount >= Self.keyRollOver {
            // you are cheating. only one human typist (fingers <= 10) is supported.
            return
        }
        chordKeyCodes[chordKeyCount] = keycode
        chordModifiers[chordKeyCount] = modifiers
        chordKeyCount += 1
        // reset timer
        if let timer = chordTimer, timer.isValid {
            timer.invalidate()
        }
        chordDuration = 0.1
        if let duration = NSApp.squirrelAppDelegate.config?.getDouble("chord_duration"),
            duration > 0
        {
            chordDuration = duration
        }
        chordTimer = Timer.scheduledTimer(
            withTimeInterval: chordDuration, repeats: false, block: onChordTimer)
    }

    fileprivate func clearChord() {
        chordKeyCount = 0
        if let timer = chordTimer {
            if timer.isValid {
                timer.invalidate()
            }
            chordTimer = nil
        }
    }

    fileprivate func createSession() {
        let app =
            client?.bundleIdentifier()
            ?? {
                SquirrelInputController.unknownAppCnt &+= 1
                return "UnknownApp\(SquirrelInputController.unknownAppCnt)"
            }()
        print("createSession: \(app)")
        currentApp = app
        session = rimeAPI.create_session()
        schemaId = ""

        if session != 0 {
            updateAppOptions()
            // 初始化异步处理器
            //asyncProcessor = AsyncRimeProcessor(rimeAPI: rimeAPI, session: session, delegate: self)
            //用同步处理，在panel上加定时器来更新内容
            asyncProcessor = nil
        }
    }

    fileprivate func updateAppOptions() {
        if currentApp == "" {
            return
        }
        if let appOptions = NSApp.squirrelAppDelegate.config?.getAppOptions(currentApp) {
            for (key, value) in appOptions {
                print("set app option: \(key) = \(value)")
                rimeAPI.set_option(session, key, value)
            }
        }
    }

    fileprivate func destroySession() {
        // print("[DEBUG] destroySession:")
        if session != 0 {
            _ = rimeAPI.destroy_session(session)
            session = 0
        }
        clearChord()
    }

    fileprivate func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
        // 检测空格键（用于统计）
        if Int32(rimeKeycode) == XK_space && (rimeModifiers & kReleaseMask.rawValue) == 0 {
            InputStatsManager.shared.markProcessingSpace()
        }

        if let processor = asyncProcessor {
            // 异步模式：立即更新选项并异步处理按键
            if let panel = NSApp.squirrelAppDelegate.panel {
                if panel.linear != processor.getOption("_linear") {
                    processor.setOption("_linear", value: panel.linear)
                }
                if panel.vertical != processor.getOption("_vertical") {
                    processor.setOption("_vertical", value: panel.vertical)
                }
            }

            // 异步处理按键
            let handled = processor.processKeyAsync(rimeKeycode, modifiers: rimeModifiers)

            // TODO add special key event postprocessing here
            if handled {
                let isChordingKey =
                    switch Int32(rimeKeycode) {
                    case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R,
                        XK_Shift_L, XK_Shift_R:
                        true
                    default:
                        false
                    }
                if isChordingKey && processor.getOption("_chord_typing") {
                    updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
                } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
                    // non-chording key pressed
                    clearChord()
                }
            }

            return handled
        } else {
            // 回退到同步模式
            // with linear candidate list, arrow keys may behave differently.
            if let panel = NSApp.squirrelAppDelegate.panel {
                if panel.linear != rimeAPI.get_option(session, "_linear") {
                    rimeAPI.set_option(session, "_linear", panel.linear)
                }
                // with vertical text, arrow keys may behave differently.
                if panel.vertical != rimeAPI.get_option(session, "_vertical") {
                    rimeAPI.set_option(session, "_vertical", panel.vertical)
                }
            }

            let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))
            // print("[DEBUG] rime_keycode: \(rimeKeycode), rime_modifiers: \(rimeModifiers), handled = \(handled)")

            // TODO add special key event postprocessing here

            if !handled {
                let isVimBackInCommandMode =
                    rimeKeycode == XK_Escape
                    || ((rimeModifiers & kControlMask.rawValue != 0)
                        && (rimeKeycode == XK_c || rimeKeycode == XK_C
                            || rimeKeycode == XK_bracketleft))
                if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode")
                    && !rimeAPI.get_option(session, "ascii_mode")
                {
                    rimeAPI.set_option(session, "ascii_mode", true)
                    // print("[DEBUG] turned Chinese mode off in vim-like editor's command mode")
                }
            } else {
                let isChordingKey =
                    switch Int32(rimeKeycode) {
                    case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R,
                        XK_Shift_L, XK_Shift_R:
                        true
                    default:
                        false
                    }
                if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
                    updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
                } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
                    // non-chording key pressed
                    clearChord()
                }
            }

            return handled
        }
    }

    fileprivate func rimeConsumeCommittedText() {
        var commitText = RimeCommit.rimeStructInit()
        if rimeAPI.get_commit(session, &commitText) {
            if let text = commitText.text {
                commit(string: String(cString: text))
            }
            _ = rimeAPI.free_commit(&commitText)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func rimeUpdate(forceShowPanel: Bool = false) {
        // print("[DEBUG] rimeUpdate")
        rimeConsumeCommittedText()

        var status = RimeStatus_stdbool.rimeStructInit()
        if rimeAPI.get_status(session, &status) {
            // enable schema specific ui style
            // swiftlint:disable:next identifier_name
            if let schema_id = status.schema_id,
                schemaId == "" || schemaId != String(cString: schema_id)
            {
                schemaId = String(cString: schema_id)
                NSApp.squirrelAppDelegate.loadSettings(for: schemaId)
                // inline preedit
                if let panel = NSApp.squirrelAppDelegate.panel {
                    inlinePreedit =
                        (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline"))
                        || rimeAPI.get_option(session, "inline")
                    inlineCandidate =
                        panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
                    // if not inline, embed soft cursor in preedit string
                    rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
                }
            }
            _ = rimeAPI.free_status(&status)
        }

        var ctx = RimeContext_stdbool.rimeStructInit()
        if rimeAPI.get_context(session, &ctx) {
            // update preedit text
            let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

            let start =
                String.Index(
                    preedit.utf8.index(
                        preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)),
                    within: preedit) ?? preedit.startIndex
            let end =
                String.Index(
                    preedit.utf8.index(
                        preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)),
                    within: preedit) ?? preedit.startIndex
            let caretPos =
                String.Index(
                    preedit.utf8.index(
                        preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)),
                    within: preedit) ?? preedit.startIndex

            if inlineCandidate {
                var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
                let endOfCandidatePreview = candidatePreview.endIndex
                if inlinePreedit {
                    // 左移光標後的情形：
                    // preedit:             ^已選某些字[xiang zuo yi dong]|guangbiao$
                    // commit_text_preview: ^已選某些字向左移動$
                    // candidate_preview:   ^已選某些字[向左移動]|guangbiao$
                    // 繼續翻頁至指定更短字詞的情形：
                    // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
                    // commit_text_preview: ^已選某些字向左yidong$
                    // candidate_preview:   ^已選某些字[向左]yidong|guangbiao$
                    // 光標移至當前段落最左端的情形：
                    // preedit:             ^已選某些字|[xiang zuo yi dong guang biao]$
                    // commit_text_preview: ^已選某些字向左移動光標$
                    // candidate_preview:   ^已選某些字|[向左移動光標]$
                    // 討論：
                    // preedit 與 commit_text_preview 中“已選某些字”部分一致
                    // 因此，選中範圍即正在翻譯的碼段“向左移動”中，兩者的 start 值一致
                    // 光標位置的範圍是 start ..= endOfCandidatePreview
                    if caretPos >= end && caretPos < preedit.endIndex {
                        // 從 preedit 截取光標後未翻譯的編碼“guangbiao”
                        candidatePreview += preedit[caretPos...]
                    }
                } else {
                    // 翻頁至指定更短字詞的情形：
                    // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
                    // commit_text_preview: ^已選某些字向左yidongguangbiao$
                    // candidate_preview:   ^已選某些字[向左???]|$
                    // 光標移至當前段落最左端，繼續翻頁至指定更短字詞的情形：
                    // preedit:             ^已選某些字|[xiang zuo]yidongguangbiao$
                    // commit_text_preview: ^已選某些字向左yidongguangbiao$
                    // candidate_preview:   ^已選某些字|[向左]???$
                    // FIXME: add librime APIs to support preview candidate without remaining code.
                }
                // preedit can contain additional prompt text before start:
                // ^(prompt)[selection]$
                let start = min(start, candidatePreview.endIndex)
                // caret can be either before or after the selected range.
                let caretPos = caretPos <= start ? caretPos : endOfCandidatePreview
                show(
                    preedit: candidatePreview,
                    selRange: NSRange(
                        location: start.utf16Offset(in: candidatePreview),
                        length: candidatePreview.utf16.distance(
                            from: start, to: candidatePreview.endIndex)),
                    caretPos: caretPos.utf16Offset(in: candidatePreview))
            } else {
                if inlinePreedit {
                    show(
                        preedit: preedit,
                        selRange: NSRange(
                            location: start.utf16Offset(in: preedit),
                            length: preedit.utf16.distance(from: start, to: end)),
                        caretPos: caretPos.utf16Offset(in: preedit))
                } else {
                    // TRICKY: display a non-empty string to prevent iTerm2 from echoing
                    // each character in preedit. note this is a full-shape space U+3000;
                    // using half shape characters like "..." will result in an unstable
                    // baseline when composing Chinese characters.
                    show(
                        preedit: preedit.isEmpty ? "" : "　",
                        selRange: NSRange(location: 0, length: 0), caretPos: 0)
                }
            }

            // update candidates
            let numCandidates = Int(ctx.menu.num_candidates)
            var candidates = [String]()
            var comments = [String]()
            for i in 0..<numCandidates {
                let candidate = ctx.menu.candidates[i]
                candidates.append(candidate.text.map { String(cString: $0) } ?? "")
                comments.append(candidate.comment.map { String(cString: $0) } ?? "")
            }
            var labels = [String]()
            // swiftlint:disable identifier_name
            if let select_keys = ctx.menu.select_keys {
                labels = String(cString: select_keys).map { String($0) }
            } else if let select_labels = ctx.select_labels {
                let pageSize = Int(ctx.menu.page_size)
                for i in 0..<pageSize {
                    labels.append(select_labels[i].map { String(cString: $0) } ?? "")
                }
            }
            // swiftlint:enable identifier_name
            let page = Int(ctx.menu.page_no)
            let lastPage = ctx.menu.is_last_page

            let selRange = NSRange(
                location: start.utf16Offset(in: preedit),
                length: preedit.utf16.distance(from: start, to: end))
            showPanel(
                preedit: inlinePreedit ? "" : preedit, selRange: selRange,
                caretPos: caretPos.utf16Offset(in: preedit),
                candidates: candidates, comments: comments, labels: labels,
                highlighted: Int(ctx.menu.highlighted_candidate_index),
                page: page, lastPage: lastPage)
            _ = rimeAPI.free_context(&ctx)
        } else {
            // 在异步模式下，如果有活跃输入则不隐藏面板
            if let processor = asyncProcessor {
                if !forceShowPanel && !processor.hasInput() {
                    hidePalettes()
                }
                // 如果 forceShowPanel 为 true 或有输入内容，保持面板显示
            } else {
                // 同步模式下的原有逻辑
                hidePalettes()
            }
        }
    }

    fileprivate func commit(string: String) {
        guard let client = client else { return }
        // print("[DEBUG] commitString: \(string)")
        client.insertText(string, replacementRange: .empty)
        preedit = ""
        hidePalettes()

        // 记录输入统计
        let isSpaceTriggered = InputStatsManager.shared.checkAndClearSpaceFlag()
        InputStatsManager.shared.recordCommit(text: string, isSpaceTriggered: isSpaceTriggered)
    }

    fileprivate func show(preedit: String, selRange: NSRange, caretPos: Int) {
        guard let client = client else { return }
        // print("[DEBUG] showPreeditString: '\(preedit)'")
        if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
            return
        }

        self.preedit = preedit
        self.caretPos = caretPos
        self.selRange = selRange

        // print("[DEBUG] selRange.location = \(selRange.location), selRange.length = \(selRange.length); caretPos = \(caretPos)")
        let start = selRange.location
        let attrString = NSMutableAttributedString(string: preedit)
        if start > 0 {
            let attrs =
                mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))!
                as! [NSAttributedString.Key: Any]
            attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
        }
        let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
        let attrs =
            mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)!
            as! [NSAttributedString.Key: Any]
        attrString.setAttributes(attrs, range: remainingRange)
        client.setMarkedText(
            attrString, selectionRange: NSRange(location: caretPos, length: 0),
            replacementRange: .empty)
    }

    // swiftlint:disable:next function_parameter_count
    fileprivate func showPanel(
        preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String],
        labels: [String], highlighted: Int, page: Int, lastPage: Bool
    ) {
        // print("[DEBUG] showPanelWithPreedit:...:")
        guard let client = client else { return }
        var inputPos = NSRect()
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)
        if let panel = NSApp.squirrelAppDelegate.panel {
            panel.position = inputPos
            panel.inputController = self
            panel.update(
                preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates,
                comments: comments, labels: labels,
                highlighted: highlighted, page: page, lastPage: lastPage, update: true)
        }
    }
}

// MARK: - Context Insertion (Command+I)
extension SquirrelInputController {
    /// 处理 Command+I 快捷键，插入应用程序名称和上下文信息
    fileprivate func handleContextInsertionShortcut() -> Bool {
        // 获取应用程序名称
        let appName = getActiveApplicationName()

        // 获取光标上方最多 3 行文本
        let contextText = getContextText(lines: 3)

        // 格式化并插入
        let insertionText = formatContextInsertion(app: appName, context: contextText)
        commit(string: insertionText)

        return true
    }

    /// 获取当前活跃应用程序的名称
    fileprivate func getActiveApplicationName() -> String {
        // 优先使用 Bundle Identifier
        if let bundleId = client?.bundleIdentifier(), !bundleId.isEmpty {
            // 尝试从 Bundle ID 提取应用名称
            // 例如: com.apple.TextEdit -> TextEdit
            let components = bundleId.split(separator: ".")
            if let appName = components.last {
                return String(appName)
            }
            return bundleId
        }

        // 如果无法获取，使用当前存储的 currentApp
        if !currentApp.isEmpty {
            let components = currentApp.split(separator: ".")
            if let appName = components.last {
                return String(appName)
            }
            return currentApp
        }

        return "Unknown App"
    }

    /// 通过 IMKTextInput 协议获取光标上方的文本内容
    /// - Parameter lines: 需要获取的行数（默认 3 行）
    /// - Returns: 获取到的文本，失败返回 nil
    fileprivate func getContextText(lines: Int) -> String? {
        guard let client = client else { return nil }

        // 获取当前光标位置
        let selectedRange = client.selectedRange()
        let cursorPosition = selectedRange.location

        // 如果光标在文档开头，无法获取上下文
        if cursorPosition <= 0 {
            return nil
        }

        // 尝试向前读取最多 500 个字符（足够包含 3 行文本）
        let maxReadLength = 500
        let startPos = max(0, cursorPosition - maxReadLength)
        let readLength = cursorPosition - startPos

        if readLength <= 0 {
            return nil
        }

        let range = NSRange(location: startPos, length: readLength)

        // 尝试获取文本
        guard let attrString = client.attributedSubstring(from: range) else {
            return nil
        }

        let text = attrString.string

        // 从文本中提取最后 N 行
        return extractLastNLines(from: text, count: lines)
    }

    /// 从文本中提取最后 N 行
    /// - Parameters:
    ///   - text: 源文本
    ///   - count: 需要提取的行数
    /// - Returns: 提取的文本
    fileprivate func extractLastNLines(from text: String, count: Int) -> String {
        if text.isEmpty {
            return ""
        }

        // 按换行符分割文本
        let lines = text.components(separatedBy: .newlines)

        // 获取最后 N 行（去除空行）
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if nonEmptyLines.isEmpty {
            return ""
        }

        // 取最后 N 行
        let lastNLines = nonEmptyLines.suffix(count)

        return lastNLines.joined(separator: "\n")
    }

    /// 格式化上下文插入的文本
    /// - Parameters:
    ///   - app: 应用程序名称
    ///   - context: 上下文文本（可选）
    /// - Returns: 格式化后的文本
    fileprivate func formatContextInsertion(app: String, context: String?) -> String {
        var result = "[App: \(app)]"

        if let context = context, !context.isEmpty {
            result += "\n" + context
        }

        return result
    }
}
