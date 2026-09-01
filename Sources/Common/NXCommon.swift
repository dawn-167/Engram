import Cocoa

// MARK: - Nexus CommonKit 共享入口
// CommonKit Version: 1.0
// 此目录下的代码为 Nexus 元宇宙所有应用共享
// 修改应提交到 nexus-common 仓库，再同步到各应用

/// Nexus 元宇宙信息
public enum NXMeta {
    public static let version = "1.0"
    public static let organization = "Nexus"
    public static let bundlePrefix = "com.nexus"
}

/// 应用分类
public enum NXAppCategory: String {
    case tool      // 工具类
    case life      // 生活类
    case game      // 游戏类
    case create    // 创意类
    case system    // 系统类
}
