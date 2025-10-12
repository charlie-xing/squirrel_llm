//
//  AIPluginWindowManager.swift
//  Squirrel
//
//  AI Plugin Window Manager
//  管理 AI 插件窗口的显示和隐藏
//

import AppKit
import SwiftUI

final class AIPluginWindowManager: NSObject {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var isWindowVisible = false
    private let windowFrameKey = "AIPluginWindowFrame"

    override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        // 创建 AI Plugins 的主视图
        let mainView = MainView()
        let rootView = AnyView(mainView)

        hostingController = NSHostingController(rootView: rootView)

        // 创建窗口 - 设置默认尺寸（减少 1/3 高度：720 -> 480）
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "AI plugin helper"
        window?.contentViewController = hostingController
        window?.minSize = NSSize(width: 900, height: 400)

        // 设置窗口级别和行为
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 设置窗口代理
        window?.delegate = self

        // 恢复窗口位置或居中
        restoreWindowFrame()

        // 初始隐藏窗口
        window?.orderOut(nil)
    }

    /// 切换窗口显示/隐藏
    func toggleWindow() {
        guard let window = window else { return }

        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    /// 显示窗口
    func showWindow() {
        guard let window = window else { return }

        // 临时提升应用激活策略，确保窗口可以显示
        let previousPolicy = NSApp.activationPolicy()

        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        // 每次显示时都居中到屏幕中央
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isWindowVisible = true

        // 延迟恢复激活策略（给窗口显示时间）
        if previousPolicy == .accessory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 保持 regular 策略，这样窗口才能保持显示
                // NSApp.setActivationPolicy(previousPolicy)
            }
        }
    }

    /// 隐藏窗口
    func hideWindow() {
        guard let window = window else { return }

        // 保存窗口位置
        saveWindowFrame()

        window.orderOut(nil)
        isWindowVisible = false

        // 恢复输入法的后台状态
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Window Frame Persistence

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        let frameString = NSStringFromRect(frame)
        UserDefaults.standard.set(frameString, forKey: windowFrameKey)
    }

    private func restoreWindowFrame() {
        guard let frameString = UserDefaults.standard.string(forKey: windowFrameKey),
            let window = window
        else {
            // 如果没有保存的位置，居中显示
            window?.center()
            return
        }
        let frame = NSRectFromString(frameString)

        // 验证 frame 是否有效
        if frame.width > 0 && frame.height > 0 {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }
}

// MARK: - NSWindowDelegate

extension AIPluginWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
        saveWindowFrame()
        // 恢复输入法的后台状态
        NSApp.setActivationPolicy(.accessory)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 点击关闭按钮时隐藏而不是销毁窗口
        hideWindow()
        return false
    }

    func windowDidResize(_ notification: Notification) {
        // 窗口大小改变时自动保存
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        // 窗口位置改变时自动保存
        saveWindowFrame()
    }
}
