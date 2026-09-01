import Cocoa

// MARK: - Nexus 跨应用 URL Scheme 通信
// CommonKit Version: 1.0
// 所有 Nexus 应用通过统一的 URL Scheme 互相唤起和传递数据
//
// URL 格式: nexus-<appid>://<action>?<params>
// 示例:
//   nexus-keyhub://              - 唤起并显示窗口
//   nexus-keyhub://search?q=xxx  - 唤起并搜索
//   nexus-keyhub://open?guide=ltspice  - 唤起并打开指定指南

public enum NXURLScheme {

    // MARK: - 打开其他 Nexus 应用

    /// 打开指定的 Nexus 应用
    /// - Parameters:
    ///   - appId: 应用标识，如 "keyhub"
    ///   - action: 可选操作，如 "search"
    ///   - params: 可选参数字典
    /// - Returns: 是否成功打开
    @discardableResult
    public static func openApp(appId: String, action: String? = nil, params: [String: String] = [:]) -> Bool {
        var urlString = "nexus-\(appId)://"
        if let action = action, !action.isEmpty {
            urlString += action
        }
        if !params.isEmpty {
            let query = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                .joined(separator: "&")
            urlString += "?\(query)"
        }
        guard let url = URL(string: urlString) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// 打开 Nexus Hub（元宇宙中心平台，如已安装）
    @discardableResult
    public static func openHub() -> Bool {
        openApp(appId: "hub")
    }

    /// 检查指定 Nexus 应用是否已安装（通过 URL Scheme 能否处理）
    public static func isAppInstalled(appId: String) -> Bool {
        guard let url = URL(string: "nexus-\(appId)://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    // MARK: - 解析收到的 URL

    /// 解析 Nexus URL Scheme
    /// - Parameter url: 收到的 URL
    /// - Returns: 解析结果（action + params），非 Nexus URL 返回 nil
    public static func parse(_ url: URL) -> (action: String, params: [String: String])? {
        guard url.scheme?.hasPrefix("nexus-") == true else { return nil }
        let action = url.host ?? ""
        var params: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }
        return (action, params)
    }
}
