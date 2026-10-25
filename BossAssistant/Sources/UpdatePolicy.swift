import Foundation

struct AppVersion:Comparable,Equatable {
    let parts:[Int]
    init?(_ value:String){
        let text=value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields=text.split(separator:".",omittingEmptySubsequences:false)
        guard fields.count==3,fields.allSatisfy({!$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber})}),fields.allSatisfy({Int($0) != nil}) else{return nil}
        parts=fields.map{Int($0)!}
    }
    static func <(a:Self,b:Self)->Bool{a.parts.lexicographicallyPrecedes(b.parts)}
}
struct ReleaseAsset:Decodable {let name:String;let browser_download_url:URL;let size:Int64}
struct AppRelease:Decodable,Identifiable {
    let tag_name:String;let body:String?;let html_url:URL;let draft:Bool;let prerelease:Bool;let assets:[ReleaseAsset]
    var id:String{tag_name}
    var version:String{String(tag_name.dropFirst())}
    var archiveName:String{"BossAssistant-\(version)-macos-arm64.zip"}
    var archive:ReleaseAsset?{assets.first{$0.name==archiveName}}
    var checksum:ReleaseAsset?{assets.first{$0.name==archiveName+".sha256"}}
}
enum UpdatePolicy {
    static let repository="HuLuca1998/boss"
    static let bundleID="local.luca.HeroBossAssistant"
    static let certificate="B6D3E9976B2192AAB7A6AE143C3A9012D7C101DA"
    static let requirement="identifier \"\(bundleID)\" and certificate leaf = H\"\(certificate)\""
    static func releases(_ list:[AppRelease])->[AppRelease]{
        list.filter{!$0.draft && !$0.prerelease && $0.tag_name.hasPrefix("v") && AppVersion($0.version) != nil && $0.archive != nil && $0.checksum != nil}.sorted{AppVersion($0.version)! > AppVersion($1.version)!}
    }
    static func allowed(_ url:URL,version:String,name:String)->Bool{
        url.scheme=="https" && url.host=="github.com" && url.user==nil && url.password==nil && url.query==nil && url.fragment==nil && url.path=="/\(repository)/releases/download/v\(version)/\(name)"
    }
    static func checksum(_ text:String,filename:String)->String?{
        let fields=text.trimmingCharacters(in:.whitespacesAndNewlines).split(whereSeparator:{$0.isWhitespace})
        guard fields.count==2,fields[1]==Substring(filename),fields[0].count==64,fields[0].allSatisfy({$0.isASCII && $0.isHexDigit}) else{return nil}
        return fields[0].lowercased()
    }
    static func safeArchive(_ data:Data)->Bool{
        // Read the ZIP central directory before extraction; this app needs no symlinks or ZIP64.
        func u16(_ i:Int)->Int{Int(data[i]) | Int(data[i+1])<<8}
        func u32(_ i:Int)->UInt32{UInt32(data[i]) | UInt32(data[i+1])<<8 | UInt32(data[i+2])<<16 | UInt32(data[i+3])<<24}
        guard data.count>=22 else{return false}
        var end:Int?
        for i in stride(from:data.count-22,through:max(0,data.count-65557),by:-1){if u32(i)==0x06054b50 && i+22+u16(i+20)==data.count{end=i;break}}
        guard let end,u16(end+4)==0,u16(end+6)==0,u16(end+8)==u16(end+10) else{return false}
        let count=u16(end+10);var offset=Int(u32(end+16));var expanded:UInt64=0
        guard count>0,count<5000,offset<end else{return false}
        for _ in 0..<count {
            guard offset+46<=end,u32(offset)==0x02014b50,u16(offset+8)&1==0 else{return false}
            let length=u16(offset+28),extra=u16(offset+30),comment=u16(offset+32)
            guard offset+46+length+extra+comment<=end,let name=String(data:data[(offset+46)..<(offset+46+length)],encoding:.utf8),!name.contains("\\"),!name.contains("\0"),!name.hasPrefix("/"),!name.split(separator:"/").contains(".."),name.hasPrefix("首领助手.app/") || name.hasPrefix("__MACOSX/") else{return false}
            let mode=(u32(offset+38)>>16)&0xf000
            guard mode==0 || mode==0x8000 || mode==0x4000 else{return false}
            expanded+=UInt64(u32(offset+24));guard expanded<1_000_000_000 else{return false}
            offset+=46+length+extra+comment
        }
        return offset==end
    }
}
