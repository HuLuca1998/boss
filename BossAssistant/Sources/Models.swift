import Foundation
struct Region:Codable,Identifiable,Hashable {let id:Int;let name:String;var unlocked:Bool?;var current:Bool?}
struct Boss:Codable,Identifiable,Hashable {
    var kind:String?=nil
    var keyItemId:Int?=nil
    var keyCount:Int?=nil
    var isAreaBoss:Bool {kind=="areaBoss"}
    var id:String {"\(insId)-\(pointId)"}
    let name:String;let bossId:Int;let insId:Int;let mapId:Int;let pointId:Int;let pointIndex:Int
    let loaded:Bool;let reviveTime:Double?;let cdSeconds:Double?;let blocked:Bool?;let status:String
    var statusLabel:String {switch status{case "ready":return "已刷新";case "cooldown":return "冷却中";case "blocked":return "未解锁";default:return "待检测"}}
    var countdown:String {guard let cdSeconds else{return "—"};let v=max(0,Int(cdSeconds));return v==0 ? "可前往" : String(format:"%02d:%02d",v/60,v%60)}
}
struct Snapshot:Codable {
    var navigation:BossNavigation?=nil
    var areaBossKey:AreaBossKey?=nil
    var areaBossVersion:Int?=nil
    let areaId:Int;let fieldId:Int;let serverTime:Double;let rows:[Boss]
    let areaName:String?;let fieldName:String?;let areas:[Region]?
    let keyboard:KeyboardStatus?
    let location:GameLocation?
    let isTeleporting:Bool?
    let runtimeVersion:Int?
}
struct EscapeStatus:Codable {let closed:Bool;let reason:String?;let viewId:Int?;let at:Double}
struct KeyboardStatus:Codable {let enabled:Bool;let pressed:[Int]?;let sceneType:Int?;let escape:EscapeStatus?}
struct CatalogBoss:Codable {
    let boss_name:String;let boss_id:Int;let field_name:String;let field_id:Int;let area_id:Int
    let instance_id:Int;let map_id:Int;let point_id:Int;let point_index:Int;let point_type:Int
    var boss:Boss{Boss(kind:point_type==3 ? "areaBoss" : "normal",name:boss_name,bossId:boss_id,insId:instance_id,mapId:map_id,pointId:point_id,pointIndex:point_index,loaded:false,reviveTime:nil,cdSeconds:nil,blocked:nil,status:"unknown")}
}
struct Activity:Identifiable {let id=UUID();let time=Date();let text:String}

struct GameLocation:Codable {
    let kind:String
    let name:String
    let sceneType:Int
    let ready:Bool
    let gameTime:Double?
    let dungeonId:Int?
    let heroPos:GamePosition?
}
struct GamePosition:Codable {let x:Double;let y:Double;let z:Double}
enum HuntLocationGate:Equatable {
    case ready, transition, away, unsupported
    static func evaluate(_ snapshot:Snapshot,area:Int)->HuntLocationGate {
        guard let location=snapshot.location else{return .unsupported}
        if location.kind == "dungeon" {return .away}
        if location.kind == "wild",snapshot.areaId != area {return .away}
        if location.kind != "wild" || !location.ready || snapshot.isTeleporting == true {return .transition}
        return .ready
    }
}

struct AreaBossKey:Codable,Equatable {let itemId:Int;let count:Int;let limit:Int?}

struct BossNavigation:Codable {let bossId:Int;let phase:String;let mode:String?;let error:String?;let distance:Double?}
