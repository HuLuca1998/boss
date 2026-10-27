import Foundation

struct EquipmentPart:Codable,Identifiable {let id:Int;let name:String}
struct BossDropInfo:Codable {
    let parts:[Int]
    let names:[String]
    let minLevel:Int?
    let maxLevel:Int?
    var partText:String {names.isEmpty ? "暂无预览" : names.joined(separator:" / ")}
    var levelText:String {
        guard let minLevel,let maxLevel,minLevel>0,maxLevel>0 else{return "—"}
        return minLevel==maxLevel ? "\(minLevel)级" : "\(minLevel)～\(maxLevel)级"
    }
}

/// An untouched area includes all bosses; an explicit empty set includes none.
struct BossSelection:Codable {
    private(set) var areas:[Int:Set<String>]=[:]
    var desiredParts:Set<Int>=[]
    func checked(_ id:String,area:Int)->Bool {areas[area]?.contains(id) ?? true}
    func matches(parts:[Int]?)->Bool {desiredParts.isEmpty || !(Set(parts ?? []).isDisjoint(with:desiredParts))}
    func permits(_ id:String,area:Int,parts:[Int]?)->Bool {checked(id,area:area) && matches(parts:parts)}
    mutating func set(_ id:String,area:Int,selected:Bool,knownIDs:Set<String>){
        var ids=areas[area] ?? knownIDs
        if selected {ids.insert(id)} else{ids.remove(id)}
        areas[area]=ids
    }
    mutating func setVisible(_ ids:Set<String>,area:Int,selected:Bool,knownIDs:Set<String>){
        var selection=areas[area] ?? knownIDs
        if selected {selection.formUnion(ids)} else{selection.subtract(ids)}
        areas[area]=selection
    }
}
