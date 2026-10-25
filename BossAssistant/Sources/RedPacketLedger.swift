import Foundation

struct PacketRecord:Codable,Equatable {
    let key:String
    let id:String
    let channel:Int
    let type:Int
    var sentAt:Double?=nil
    var requestDelayMs:Double?=nil
    var seenAt:Double
    let expires:Double
    let status:String
    let attempted:Bool
    let name:String?
    let currencyId:Int?
    let currencyName:String?
    let serverStatus:Int?
    let totalMoney:Double?
    let totalNum:Int?
    let remainingNum:Int?
    let myAmount:Double?
    var confirmed:Bool {serverStatus==1 && myAmount != nil}
    var result:String {
        if confirmed {return attempted ? "已领取（自动）" : "已领取（此前或手动）"}
        if status=="restricted" {return "受领取上限或资格限制"}
        if status=="mismatch" {return "信息不匹配，未领取"}
        if serverStatus==3 || status=="expired" {return "已过期"}
        if serverStatus==2 {return "已领完"}
        return attempted ? "已请求领取，待服务器核验" : "待查询/领取"
    }
    var channelName:String {channel==1000 ? "世界" : channel==1004 ? "联盟" : "其他"}
    var moneyName:String {currencyName ?? currencyId.map{"货币\($0)"} ?? "未知货币"}
}
struct RedPacketLedger:Codable {
    private(set) var records:[PacketRecord]=[]
    mutating func merge(_ incoming:[PacketRecord])->[PacketRecord] {
        var changes:[PacketRecord]=[]
        for var packet in incoming {
            if let index=records.firstIndex(where:{$0.key==packet.key}) {
                let previous=records[index]
                packet.seenAt=min(previous.seenAt,packet.seenAt)
                // Keep a verified award even if the small in-game info cache evicts it.
                if previous.confirmed && !packet.confirmed {continue}
                if packet != previous {records[index]=packet;changes.append(packet)}
            }else {records.append(packet);changes.append(packet)}
        }
        return changes
    }
    var confirmedCount:Int {records.filter(\.confirmed).count}
    var autoCount:Int {records.filter{$0.confirmed && $0.attempted}.count}
    var totals:[String:Double] {
        var sums:[String:Double]=[:]
        for r in records where r.confirmed {sums[r.moneyName,default:0]+=r.myAmount ?? 0}
        return sums
    }
    func readable()->String {
        let formatter=ISO8601DateFormatter();formatter.timeZone=TimeZone(identifier:"Asia/Shanghai")
        func number(_ value:Double)->String {String(format:"%g",value)}
        let summary=totals.sorted{$0.key<$1.key}.map{"\($0.key) \(number($0.value))"}.joined(separator:"、")
        var lines=["聊天红包记录（本机）","发现 \(records.count) 个；助手自动领取已核验 \(autoCount) 个；含此前/手动的本角色已领取 \(confirmedCount) 个；按货币分别累计：\(summary.isEmpty ? "暂无" : summary)","已领取包含监控中发现的此前/手动领取；只有标注自动的记录归为助手请求。待核验不计入金额。",""]
        for r in records.reversed() {
            let time=formatter.string(from:Date(timeIntervalSince1970:r.seenAt/1000))
            let total=r.totalMoney.map(number) ?? "未知"
            let shares=r.totalNum.map(String.init) ?? "未知"
            let amount=r.confirmed ? "\(number(r.myAmount ?? 0)) \(r.moneyName)" : "未核验"
            lines.append("\(time) | \(r.channelName) | \(r.name ?? "聊天红包") | ID \(r.id) | 总额 \(total) \(r.moneyName) / \(shares)份 | \(r.result) | 本角色领到：\(amount)")
        }
        return lines.joined(separator:"\n")+"\n"
    }
}
