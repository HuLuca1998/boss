import Foundation
import CryptoKit

struct GameCacheFailure:LocalizedError {
    let message:String
    var errorDescription:String? {message}
}

struct GameCacheProfile:Equatable {
    let script:String
    let objectID:String
    let resource:String
    let originalHash:String
    static let supported:[GameCacheProfile]=[
        .init(script:"Main-40920.js",objectID:"9bca89d68d4700faff8d14ff2748cb746b6e4848",resource:"OriginalCache",originalHash:"4085b2c2f223e255fe5b8fa62379d02d2843671ce6def362694304a099af37a0"),
        .init(script:"Main-f648a.js",objectID:"c9a04c498816087c265e2a67f04d906464400d2b",resource:"OriginalCache-f648a",originalHash:"ebd90420ce4a88b52e3610e63b77924be99ffda0c027e7b322ecb6941d8015a2"),
        .init(script:"Main-dda2f.js",objectID:"7868a8a23d060f90b2012cfd0b9df2bcb5b7b5c3",resource:"OriginalCache-dda2f",originalHash:"033163e0aeb056f69d8c4df20a59ab181f31ff2057147fe8f58f0e139415fb53")
    ]
}

/// Resolve the active DCC tree, never an old object left behind by an update.
struct GameCacheSelection:Equatable {
    let root:String
    let profile:GameCacheProfile
    let target:URL
}

enum GameCachePolicy {
    static let needle=",__toCommonJS(Main_exports)})();"
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func validID(_ value:String)->Bool {value.count==40 && value.utf8.allSatisfy{(48...57).contains($0) || (97...102).contains($0)}}
    static func objectURL(_ id:String,base:URL)throws->URL {
        guard validID(id) else{throw GameCacheFailure(message:"游戏缓存对象编号无效，未修改游戏")}
        let url=base.appendingPathComponent("objects/\(id.prefix(2))/\(id.dropFirst(2))")
        try regularPath(url,under:base)
        return url
    }
    static func regularPath(_ url:URL,under base:URL)throws {
        var component=url.standardizedFileURL
        while component.path.hasPrefix(base.standardizedFileURL.path) {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath:component.path)) != nil {
                throw GameCacheFailure(message:"游戏缓存含符号链接，未修改游戏")
            }
            component.deleteLastPathComponent()
        }
        guard url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path+"/"),
              url.resolvingSymlinksInPath().path==url.standardizedFileURL.path,
              base.resolvingSymlinksInPath().path==base.standardizedFileURL.path else {
            throw GameCacheFailure(message:"游戏缓存路径异常，未修改游戏")
        }
    }
    struct Entry {let mode:String;let name:String;let id:String}
    static func entries(_ data:Data)throws->[Entry] {
        let b=[UInt8](data)
        guard b.count<=4_000_000,b.starts(with:Array("tree ".utf8)),let zero=b.firstIndex(of:0),
              let size=Int(String(decoding:b[5..<zero],as:UTF8.self)),size>=0,
              size==b.count-((zero+4) & ~3) else{throw GameCacheFailure(message:"游戏缓存目录格式无效")}
        var i=(zero+4) & ~3,result=[Entry]()
        while i<b.count {
            guard result.count<10000,let space=b[i...].firstIndex(of:32),let end=b[space...].firstIndex(of:0),
                  end+21<=b.count else{throw GameCacheFailure(message:"游戏缓存目录不完整")}
            let mode=String(decoding:b[i..<space],as:UTF8.self)
            let name=String(decoding:b[(space+1)..<end],as:UTF8.self)
            guard ["40000","100644"].contains(mode),!name.isEmpty,!name.contains("/"),!name.contains("\\"),name != ".",name != ".." else{throw GameCacheFailure(message:"游戏缓存目录条目异常")}
            result.append(Entry(mode:mode,name:name,id:b[(end+1)..<(end+21)].map{String(format:"%02x",$0)}.joined()))
            i=((end+24) & ~3)+8
            guard i<=b.count else{throw GameCacheFailure(message:"游戏缓存目录边界异常")}
        }
        guard Set(result.map(\.name)).count==result.count else{throw GameCacheFailure(message:"游戏缓存目录存在重名条目")}
        return result
    }
    static func resolve(base:URL)throws->GameCacheSelection {
        let head=base.appendingPathComponent("head.json");try regularPath(head,under:base)
        let raw=try Data(contentsOf:head)
        guard raw.count<65536,let h=try JSONSerialization.jsonObject(with:raw) as? [String:Any],let root=h["root"] as? String,validID(root) else{throw GameCacheFailure(message:"无法识别当前游戏热更新版本")}
        var tree=try Data(contentsOf:objectURL(root,base:base))
        if tree.starts(with:Data("commit ".utf8)) {
            guard tree.count<65536,let text=String(data:tree,encoding:.utf8),
                  let line=text.split(separator:"\n").first(where:{$0.hasPrefix("tree ")}) else{throw GameCacheFailure(message:"游戏缓存版本记录无效")}
            tree=try Data(contentsOf:objectURL(String(line.dropFirst(5)),base:base))
        }
        guard let js=try entries(tree).first(where:{$0.name=="js" && $0.mode=="40000"}) else{throw GameCacheFailure(message:"当前游戏缓存缺少脚本目录，请先正常进入游戏")}
        let scripts=try entries(Data(contentsOf:objectURL(js.id,base:base))).filter{$0.name.hasPrefix("Main-") && $0.name.hasSuffix(".js")}
        guard scripts.count==1,let script=scripts.first,script.mode=="100644" else{throw GameCacheFailure(message:"无法唯一确定当前游戏主脚本，未修改游戏")}
        guard let profile=GameCacheProfile.supported.first(where:{$0.script==script.name && $0.objectID==script.id}) else{throw GameCacheFailure(message:"游戏已热更新至 \(script.name)，当前版本尚未适配；未修改游戏")}
        return GameCacheSelection(root:root,profile:profile,target:try objectURL(script.id,base:base))
    }
    static func source(original:Data,profile:GameCacheProfile)throws->String {
        guard hash(original)==profile.originalHash,original.count>32 else{throw GameCacheFailure(message:"原始脚本校验失败，未修改游戏")}
        let key:[UInt8]=[0x8f,0xbf,0x3b,0x77,0x8f,0xc9,0x86,0xd8,0x12,0xa8,0x4c,0x9e,0xbd,0x4a,0xba,0x2d]
        let data=Data(original.dropFirst(12).dropLast(20).enumerated().map{$0.element ^ key[$0.offset%16]})
        guard let text=String(data:data,encoding:.utf8),text.components(separatedBy:needle).count==2 else{throw GameCacheFailure(message:"游戏脚本入口不匹配，未修改游戏")}
        return text
    }
    static func isInjected(_ current:Data,source:String)->Bool {
        guard let text=String(data:current,encoding:.utf8),let range=source.range(of:needle) else{return false}
        let prefix=String(source[..<range.lowerBound])+",";let suffix=String(source[range.lowerBound...])
        guard text.hasPrefix(prefix),text.hasSuffix(suffix),text.count>prefix.count+suffix.count else{return false}
        let body=text.dropFirst(prefix.count).dropLast(suffix.count)
        return body.contains("yzlm-native-boss-v2") || body.contains("yzlm-boss-bridge-v1")
    }
    static func compiled(selection:GameCacheSelection,base:URL)throws->[URL] {
        try ["arm64.cache","arm64.meta"].map {ext in
            let url=base.appendingPathComponent("codecache/\(selection.profile.script).\(ext)")
            try regularPath(url,under:base);return url
        }
    }
}
