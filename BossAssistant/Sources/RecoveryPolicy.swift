import Foundation

struct RecoveryPolicy:Codable {
    struct Hit:Codable {let token:String;let time:TimeInterval}
    private(set) var hits:[Hit]=[]
    private(set) var seen:[String]=[]
    private(set) var locked=false
    mutating func observe(token:String,now:TimeInterval){
        guard !locked,!seen.contains(token) else{return}
        seen.append(token);if seen.count>300{seen.removeFirst(seen.count-300)}
        hits=hits.filter{now-$0.time>=0 && now-$0.time<=60}
        hits.append(Hit(token:token,time:now))
        if hits.count>=2 {locked=true}
    }
    mutating func unlock(){locked=false;hits=[]}
}
struct AssistStatus:Decodable {
    struct Dialog:Decodable {let id:Int;let token:String;let kind:String;let canConfirm:Bool}
    struct ReplacedEvent:Decodable {let token:String;let time:Double}
    let noKeyBossExits:Int?
    let popupHandlingVersion:Int?
    let popupSession:String?
    let popupDropped:Int?
    let popupEvents:[PopupRecord]?
    let packets:[PacketRecord]?
    let replacedEvents:[ReplacedEvent]
    let version:Int;let session:String;let locked:Bool;let confirmations:Int;let claimed:Int;let queued:Int;let dialog:Dialog?
}
