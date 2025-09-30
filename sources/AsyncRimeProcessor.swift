//
//  AsyncRimeProcessor.swift
//  Squirrel
//
//  Created by Claude Code on 9/29/25.
//

import Foundation

protocol AsyncRimeProcessorDelegate: AnyObject {
    func onRimeStateUpdated(hasInput: Bool)
    func onRimeCommitText(_ text: String)
}

final class AsyncRimeProcessor {
    private let rimeAPI: RimeApi_stdbool
    private let session: RimeSessionId
    private weak var delegate: AsyncRimeProcessorDelegate?

    // 异步处理队列
    private let processingQueue = DispatchQueue(
        label: "com.squirrel.rime.processing", qos: .userInteractive)
    private let mainQueue = DispatchQueue.main

    // 请求管理
    private var currentRequestId: UInt64 = 0
    private let requestIdLock = NSLock()

    // 处理状态
    private var isProcessing = false
    private let processingLock = NSLock()

    // 输入状态跟踪
    private var hasActiveInput = false
    private var inputSessionActive = false  // 输入会话是否活跃
    private let inputStateLock = NSLock()

    init(rimeAPI: RimeApi_stdbool, session: RimeSessionId, delegate: AsyncRimeProcessorDelegate) {
        self.rimeAPI = rimeAPI
        self.session = session
        self.delegate = delegate
    }

    // MARK: - 异步处理核心方法

    func processKeyAsync(_ keycode: UInt32, modifiers: UInt32) -> Bool {
        // 立即返回true表示我们将处理这个按键（避免系统传递给应用）
        // 实际处理在后台进行

        let requestId = generateNewRequestId()

        processingQueue.async { [weak self] in
            self?.handleKeyProcessing(keycode: keycode, modifiers: modifiers, requestId: requestId)
        }

        return true
    }

    func selectCandidateAsync(_ index: Int) {
        let requestId = generateNewRequestId()

        processingQueue.async { [weak self] in
            self?.handleCandidateSelection(index: index, requestId: requestId)
        }
    }

    func changePageAsync(up: Bool) {
        let requestId = generateNewRequestId()

        processingQueue.async { [weak self] in
            self?.handlePageChange(up: up, requestId: requestId)
        }
    }

    func setCaretPosAsync(_ caretPos: Int) {
        let requestId = generateNewRequestId()

        processingQueue.async { [weak self] in
            self?.handleCaretChange(caretPos: caretPos, requestId: requestId)
        }
    }

    // MARK: - 私有处理方法

    private func generateNewRequestId() -> UInt64 {
        requestIdLock.lock()
        defer { requestIdLock.unlock() }
        currentRequestId += 1
        return currentRequestId
    }

    private func isRequestCurrent(_ requestId: UInt64) -> Bool {
        requestIdLock.lock()
        defer { requestIdLock.unlock() }
        return requestId == currentRequestId
    }

    private func handleKeyProcessing(keycode: UInt32, modifiers: UInt32, requestId: UInt64) {
        // 检查是否是最新请求
        guard isRequestCurrent(requestId) else {
            return  // 丢弃过时的请求
        }

        // 避免重复处理
        processingLock.lock()
        if isProcessing {
            processingLock.unlock()
            return
        }
        isProcessing = true
        processingLock.unlock()

        defer {
            processingLock.lock()
            isProcessing = false
            processingLock.unlock()
        }

        // 开始输入会话（如果还没开始）
        if !isInputSessionActive() {
            startInputSession()
        }

        // 执行实际的rime处理
        let handled = rimeAPI.process_key(session, Int32(keycode), Int32(modifiers))

        // 再次检查是否仍然是最新请求
        guard isRequestCurrent(requestId) else {
            return
        }

        if handled {
            updateRimeState(requestId: requestId)
        }
    }

    private func handleCandidateSelection(index: Int, requestId: UInt64) {
        guard isRequestCurrent(requestId) else { return }

        let success = rimeAPI.select_candidate_on_current_page(session, index)
        if success {
            updateRimeState(requestId: requestId)
        }
    }

    private func handlePageChange(up: Bool, requestId: UInt64) {
        guard isRequestCurrent(requestId) else { return }

        let handled = rimeAPI.change_page(session, up)
        if handled {
            updateRimeState(requestId: requestId)
        }
    }

    private func handleCaretChange(caretPos: Int, requestId: UInt64) {
        guard isRequestCurrent(requestId) else { return }

        rimeAPI.set_caret_pos(session, caretPos)
        updateRimeState(requestId: requestId)
    }

    private func updateRimeState(requestId: UInt64) {
        // 处理提交的文本
        consumeCommittedText(requestId: requestId)

        // 更新输入状态
        let hasInput = updateInputState()

        // 通知主线程更新UI
        guard isRequestCurrent(requestId) else { return }

        mainQueue.async { [weak self] in
            // 最后一次检查，确保UI更新时仍然是最新状态
            guard let self = self, self.isRequestCurrent(requestId) else { return }
            self.delegate?.onRimeStateUpdated(hasInput: hasInput)
        }
    }

    private func consumeCommittedText(requestId: UInt64) {
        var commitText = RimeCommit.rimeStructInit()
        if rimeAPI.get_commit(session, &commitText) {
            if let text = commitText.text {
                let textString = String(cString: text)

                // 确保仍然是最新请求再提交文本
                guard isRequestCurrent(requestId) else {
                    _ = rimeAPI.free_commit(&commitText)
                    return
                }

                // 文本提交后结束输入会话
                endInputSession()

                mainQueue.async { [weak self] in
                    guard let self = self, self.isRequestCurrent(requestId) else { return }
                    self.delegate?.onRimeCommitText(textString)
                }
            }
            _ = rimeAPI.free_commit(&commitText)
        }
    }

    // MARK: - 同步方法（用于需要立即结果的操作）

    func getRimeContext() -> RimeContext_stdbool? {
        var ctx = RimeContext_stdbool.rimeStructInit()
        if rimeAPI.get_context(session, &ctx) {
            return ctx
        }
        return nil
    }

    func getRimeStatus() -> RimeStatus_stdbool? {
        var status = RimeStatus_stdbool.rimeStructInit()
        if rimeAPI.get_status(session, &status) {
            return status
        }
        return nil
    }

    func freeContext(_ ctx: inout RimeContext_stdbool) {
        _ = rimeAPI.free_context(&ctx)
    }

    func freeStatus(_ status: inout RimeStatus_stdbool) {
        _ = rimeAPI.free_status(&status)
    }

    func getOption(_ option: String) -> Bool {
        return rimeAPI.get_option(session, option)
    }

    func setOption(_ option: String, value: Bool) {
        rimeAPI.set_option(session, option, value)
    }

    func clearComposition() {
        rimeAPI.clear_composition(session)
        endInputSession()  // 清空输入时结束会话
    }

    func getInput() -> String? {
        guard let input = rimeAPI.get_input(session) else { return nil }
        return String(cString: input)
    }

    func getCaretPos() -> Int {
        return rimeAPI.get_caret_pos(session)
    }

    // MARK: - 输入状态管理

    private func updateInputState() -> Bool {
        inputStateLock.lock()
        defer { inputStateLock.unlock() }

        // 检查是否有输入内容
        let hasInput = (getInput()?.isEmpty == false)
        hasActiveInput = hasInput

        // 如果有输入内容，标记会话为活跃
        if hasInput {
            inputSessionActive = true
        }

        return hasInput
    }

    func hasInput() -> Bool {
        inputStateLock.lock()
        defer { inputStateLock.unlock() }
        return hasActiveInput
    }

    func isInputSessionActive() -> Bool {
        inputStateLock.lock()
        defer { inputStateLock.unlock() }
        return inputSessionActive
    }

    func startInputSession() {
        inputStateLock.lock()
        defer { inputStateLock.unlock() }
        inputSessionActive = true
    }

    func endInputSession() {
        inputStateLock.lock()
        defer { inputStateLock.unlock() }
        inputSessionActive = false
        hasActiveInput = false
    }
}
