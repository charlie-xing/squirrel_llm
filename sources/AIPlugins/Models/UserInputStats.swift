import Foundation

/// 用户输入统计数据
struct UserInputStats: Codable {
    // 基础统计数据
    var totalCharacters: Int = 0           // 总输入字符数（实际上屏的字符）
    var totalCommits: Int = 0              // 总上屏次数
    var spaceCommits: Int = 0              // 空格键触发的上屏次数
    var sessionStartTime: Date = Date()    // 会话开始时间
    var lastUpdateTime: Date = Date()      // 最后更新时间

    // 旧版兼容字段（保留用于迁移）
    var totalKeystrokes: Int = 0
    var totalAIAccepts: Int = 0

    /// 每分钟字符数（CPM - Characters Per Minute）
    var charactersPerMinute: Double {
        let elapsed = Date().timeIntervalSince(sessionStartTime) / 60.0 // 转换为分钟
        guard elapsed > 0 else { return 0 }
        return Double(totalCharacters) / elapsed
    }

    /// 空格键上屏占比（百分比）
    var spaceCommitRate: Double {
        guard totalCommits > 0 else { return 0 }
        return (Double(spaceCommits) / Double(totalCommits)) * 100.0
    }

    /// 平均输入速度（每分钟按键次数）- 保留用于兼容
    var averageKeystrokesPerMinute: Double {
        return charactersPerMinute
    }

    /// AI候选词采用率 - 使用空格上屏率作为近似值
    var aiAcceptanceRate: Double {
        return spaceCommitRate
    }

    /// 记录一次上屏事件
    /// - Parameters:
    ///   - text: 上屏的文本内容
    ///   - isSpaceTriggered: 是否由空格键触发
    mutating func recordCommit(text: String, isSpaceTriggered: Bool) {
        totalCharacters += text.count
        totalCommits += 1
        if isSpaceTriggered {
            spaceCommits += 1
        }
        lastUpdateTime = Date()

        // 同步更新旧版字段以保持兼容性
        totalKeystrokes = totalCharacters
        if isSpaceTriggered {
            totalAIAccepts += 1
        }
    }

    /// 重置统计数据
    mutating func reset() {
        totalCharacters = 0
        totalCommits = 0
        spaceCommits = 0
        totalKeystrokes = 0
        totalAIAccepts = 0
        sessionStartTime = Date()
        lastUpdateTime = Date()
    }
}
