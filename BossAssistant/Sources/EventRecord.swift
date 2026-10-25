import Foundation

struct EventRecord:Codable,Identifiable {
    var id=UUID()
    let time:Date
    let category:String
    let title:String
    let data:[String:String]
    static func category(for text:String)->String {
        if text.contains("红包"){return "红包"}
        if text.contains("异地登录") || text.contains("保护"){return "账号保护"}
        if text.contains("连接") || text.contains("登录") || text.contains("响应超时"){return "连接"}
        if text.contains("攻略") || text.contains("首领") || text.contains("冷却") || text.contains("前往"){return "攻略"}
        return "操作"
    }
}
