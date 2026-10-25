import Foundation

indirect enum PopupJSON:Codable {
    case object([String:PopupJSON]),array([PopupJSON]),string(String),number(Double),bool(Bool),null
    init(from decoder:Decoder)throws {
        let value=try decoder.singleValueContainer()
        if value.decodeNil(){self = .null}
        else if let v=try? value.decode(Bool.self){self = .bool(v)}
        else if let v=try? value.decode(String.self){self = .string(v)}
        else if let v=try? value.decode(Double.self){self = .number(v)}
        else if let v=try? value.decode([String:PopupJSON].self){self = .object(v)}
        else {self = .array(try value.decode([PopupJSON].self))}
    }
    func encode(to encoder:Encoder)throws {
        var value=encoder.singleValueContainer()
        switch self {case .object(let v):try value.encode(v);case .array(let v):try value.encode(v);case .string(let v):try value.encode(v);case .number(let v):try value.encode(v);case .bool(let v):try value.encode(v);case .null:try value.encodeNil()}
    }
}
struct PopupRecord:Codable,Identifiable {
    let eventId:String
    let occurrenceId:String
    let phase:String
    let capturedAt:Double
    let viewId:Int
    let viewName:String
    let title:String
    let body:String
    let data:PopupJSON
    var supportsBlankClose:Bool {if case .object(let fields)=data,case .bool(let enabled)=fields["blankClose"] {return enabled};return false}
    var id:String {eventId}
    var displayTitle:String {viewId==1276 ? "区域BOSS掉落宝箱" : viewId==1017 ? "恭喜获得（奖励展示）" : viewId==1023 ? "挂机收益（领取奖励）" : viewId==1125 ? "场景切换提示" : viewId==1005 ? "游戏消息提示" : title}
    var phaseName:String {phase=="opened" ? "出现" : phase=="closed" ? "关闭" : phase=="rewarded" ? "服务器确认开箱" : phase=="handled" ? "自动处理" : "内容变化"}
    var sequence:Int {Int(eventId.split(separator:":").last ?? "") ?? 0}
    var readableJSON:String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return (try? encoder.encode(self)).map{String(decoding:$0,as:UTF8.self)} ?? "{}"
    }
}
