import Foundation
@main struct UpdatePolicyTests {
    static func main()throws{
        assert(AppVersion("1.3.9")! < AppVersion("1.4.0")!)
        assert(AppVersion("1.9.0")! < AppVersion("1.10.0")!)
        assert(AppVersion("v1.3.8")==AppVersion("1.3.8"))
        for value in ["1.2","1.2.3.4","1.2.beta","1.2.-1","1.2.3-pre","999999999999999999999.0.0"]{assert(AppVersion(value)==nil)}
        let name="BossAssistant-1.3.8-macos-arm64.zip"
        let valid=URL(string:"https://github.com/HuLuca1998/boss/releases/download/v1.3.8/\(name)")!
        assert(UpdatePolicy.allowed(valid,version:"1.3.8",name:name))
        for url in ["http://github.com/HuLuca1998/boss/releases/download/v1.3.8/\(name)","https://example.com/HuLuca1998/boss/releases/download/v1.3.8/\(name)",valid.absoluteString+"?token=x"]{assert(!UpdatePolicy.allowed(URL(string:url)!,version:"1.3.8",name:name))}
        let hash=String(repeating:"a",count:64)
        assert(UpdatePolicy.checksum(hash+"  "+name+"\n",filename:name)==hash)
        assert(UpdatePolicy.checksum(hash+"  wrong.zip",filename:name)==nil)
        assert(UpdatePolicy.checksum("oops  "+name,filename:name)==nil)
        func release(_ version:String,draft:Bool=false,pre:Bool=false,assets:Bool=true)->AppRelease{
            let name="BossAssistant-\(version)-macos-arm64.zip"
            return AppRelease(tag_name:"v"+version,body:"notes",html_url:valid,draft:draft,prerelease:pre,assets:assets ? [ReleaseAsset(name:name,browser_download_url:valid,size:100),ReleaseAsset(name:name+".sha256",browser_download_url:valid,size:100)] : [])
        }
        let all=[release("1.3.8"),release("1.4.0"),release("9.0.0",draft:true),release("8.0.0",pre:true),release("7.0.0",assets:false)]
        assert(UpdatePolicy.releases(all).map{$0.version}==["1.4.0","1.3.8"])
        assert(!UpdatePolicy.safeArchive(Data()))
        if CommandLine.arguments.count>1{
            let folder=URL(fileURLWithPath:CommandLine.arguments[1])
            for name in ["valid","traversal","absolute","symlink","outside"]{
                let safe=UpdatePolicy.safeArchive(try Data(contentsOf:folder.appendingPathComponent(name+".zip")))
                assert(safe == (name=="valid"),"ZIP policy: \(name)")
            }
        }
        print("PASS: numeric versions, stable release selection, exact assets/HTTPS origin, checksum format, ZIP traversal/symlink rejection")
    }
}
