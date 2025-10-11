//
//  InputStatsManager.swift
//  Squirrel
//
//  输入法统计管理器
//  负责收集、存储和管理用户输入统计数据
//

import Foundation
import AppKit

/// 输入统计数据更新通知
extension Notification.Name {
    static let inputStatsDidUpdate = Notification.Name("com.squirrel.inputStatsDidUpdate")
}

/// 输入法统计管理器（线程安全单例）
final class InputStatsManager {
    /// 单例实例
    static let shared = InputStatsManager()

    /// 统计数据存储键
    private let statsKey = "com.squirrel.input_stats"

    /// 当前统计数据（线程安全）
    private var _stats: UserInputStats
    private let statsQueue = DispatchQueue(label: "com.squirrel.statsQueue", attributes: .concurrent)

    /// 上次保存时间
    private var lastSaveTime: Date = Date()

    /// 自动保存间隔（秒）
    private let autoSaveInterval: TimeInterval = 30.0

    /// 是否正在处理空格键
    private var isProcessingSpace = false

    private init() {
        // 加载已保存的统计数据
        self._stats = Self.loadStatsFromDisk()
        print("InputStatsManager: Initialized with stats - Characters: \(_stats.totalCharacters), Commits: \(_stats.totalCommits), Space: \(_stats.spaceCommits)")

        // 注册应用退出通知，确保数据保存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// 获取当前统计数据（线程安全）
    var stats: UserInputStats {
        return statsQueue.sync { _stats }
    }

    /// 记录一次上屏事件
    /// - Parameters:
    ///   - text: 上屏的文本内容
    ///   - isSpaceTriggered: 是否由空格键触发
    func recordCommit(text: String, isSpaceTriggered: Bool) {
        guard !text.isEmpty else { return }

        statsQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // 更新统计数据
            self._stats.recordCommit(text: text, isSpaceTriggered: isSpaceTriggered)

            print("InputStatsManager: Recorded commit - Text: '\(text)', Space: \(isSpaceTriggered), Total: \(self._stats.totalCommits), CPM: \(String(format: "%.1f", self._stats.charactersPerMinute))")

            // 异步通知UI更新（在主线程）
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .inputStatsDidUpdate,
                    object: self._stats
                )
            }

            // 定期自动保存
            self.autoSaveIfNeeded()
        }
    }

    /// 标记正在处理空格键
    func markProcessingSpace() {
        isProcessingSpace = true
    }

    /// 检查并清除空格键标记
    /// - Returns: 是否刚刚处理了空格键
    func checkAndClearSpaceFlag() -> Bool {
        let wasProcessing = isProcessingSpace
        isProcessingSpace = false
        return wasProcessing
    }

    /// 重置统计数据
    func resetStats() {
        statsQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self._stats.reset()
            self.saveStatsSync()

            print("InputStatsManager: Stats reset")

            // 通知UI更新
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .inputStatsDidUpdate,
                    object: self._stats
                )
            }
        }
    }

    /// 立即保存统计数据（同步）
    func saveStatsSync() {
        statsQueue.sync {
            Self.saveStatsToDisk(_stats)
            lastSaveTime = Date()
        }
    }

    // MARK: - Private Methods

    /// 自动保存（如果需要）
    private func autoSaveIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastSaveTime) >= autoSaveInterval {
            Self.saveStatsToDisk(_stats)
            lastSaveTime = now
            print("InputStatsManager: Auto-saved stats")
        }
    }

    /// 从磁盘加载统计数据
    private static func loadStatsFromDisk() -> UserInputStats {
        guard let data = UserDefaults.standard.data(forKey: "com.squirrel.input_stats"),
              let stats = try? JSONDecoder().decode(UserInputStats.self, from: data)
        else {
            print("InputStatsManager: No saved stats found, creating new")
            return UserInputStats()
        }

        print("InputStatsManager: Loaded stats from disk")
        return stats
    }

    /// 保存统计数据到磁盘
    private static func saveStatsToDisk(_ stats: UserInputStats) {
        if let encoded = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(encoded, forKey: "com.squirrel.input_stats")
            UserDefaults.standard.synchronize()
        }
    }

    /// 应用退出时保存数据
    @objc private func applicationWillTerminate() {
        print("InputStatsManager: Application terminating, saving stats")
        saveStatsSync()
    }
}
