import Foundation
import Security
import AppKit
import Darwin

struct InstallerError:LocalizedError {let message:String;init(_ value:String){message=value};var errorDescription:String?{message}}
let fm=FileManager.default
let bundleID="local.luca.HeroBossAssistant"
let requirement="identifier \"local.luca.HeroBossAssistant\" and certificate leaf = H\"B6D3E9976B2192AAB7A6AE143C3A9012D7C101DA\""
func verify(_ app:URL,version:String?)throws {
    guard app.pathExtension=="app",let info=NSDictionary(contentsOf:app.appendingPathComponent("Contents/Info.plist")),info["CFBundleIdentifier"] as? String==bundleID else{throw InstallerError("更新包应用标识不匹配")}
    if let version,info["CFBundleShortVersionString"] as? String != version{throw InstallerError("更新包版本不匹配")}
    var code:SecStaticCode?;var rule:SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL,[],&code)==errSecSuccess,let code,
        SecRequirementCreateWithString(requirement as CFString,[],&rule)==errSecSuccess,let rule,
        SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode),rule)==errSecSuccess else{throw InstallerError("更新包签名验证失败，拒绝替换当前软件")}
    guard fm.isExecutableFile(atPath:app.appendingPathComponent("Contents/MacOS/BossAssistant").path) else{throw InstallerError("更新包缺少可执行文件")}
}
func run(_ executable:String,_ arguments:[String])throws{
    let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
    process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
    try process.run();process.waitUntilExit();guard process.terminationStatus==0 else{throw InstallerError("复制新版本失败")}
}
func result(_ status:String,_ message:String){
    let folder=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant")
    try? fm.createDirectory(at:folder,withIntermediateDirectories:true)
    if let data=try? JSONSerialization.data(withJSONObject:["status":status,"message":message,"time":Date().timeIntervalSince1970]){try? data.write(to:folder.appendingPathComponent("UpdateResult.json"),options:.atomic)}
}
func install(target:URL,staged:URL,version:String,failCopy:Bool=false)throws {
    try verify(target,version:nil);try verify(staged,version:version)
    let backup=target.deletingLastPathComponent().appendingPathComponent(".BossAssistant-backup-\(UUID().uuidString).app")
    let incoming=target.deletingLastPathComponent().appendingPathComponent(".BossAssistant-new-\(UUID().uuidString).app")
    defer{try? fm.removeItem(at:incoming)}
    try run("/usr/bin/ditto",[staged.path,incoming.path]);try verify(incoming,version:version)
    try fm.moveItem(at:target,to:backup)
    do{
        if failCopy{throw InstallerError("模拟安装失败")}
        try fm.moveItem(at:incoming,to:target);try verify(target,version:version)
    }catch{
        try? fm.removeItem(at:target)
        do{try fm.moveItem(at:backup,to:target)}catch{throw InstallerError("恢复旧版本失败，备份保留在 \(backup.path)")}
        throw error
    }
    try? fm.removeItem(at:backup)
}
do{
    let args=CommandLine.arguments
    if args.count==3,args[1]=="verify-archive"{
        guard UpdatePolicy.safeArchive(try Data(contentsOf:URL(fileURLWithPath:args[2]),options:.mappedIfSafe)) else{throw InstallerError("更新压缩包目录验证失败")};exit(0)
    }
    if args.count==4,args[1]=="verify"{try verify(URL(fileURLWithPath:args[2]),version:args[3]);exit(0)}
    #if UPDATE_TESTING
    if args.count==6,args[1]=="test-install"{
        try install(target:URL(fileURLWithPath:args[2]),staged:URL(fileURLWithPath:args[3]),version:args[4],failCopy:args[5]=="fail");exit(0)
    }
    #endif
    guard args.count==7,args[1]=="install",let parent=Int32(args[2]),parent>1 else{throw InstallerError("无效的安装参数")}
    let target=URL(fileURLWithPath:args[3]).standardizedFileURL,staged=URL(fileURLWithPath:args[4]).standardizedFileURL,directory=URL(fileURLWithPath:args[6]).standardizedFileURL
    let updates=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant/Updates").standardizedFileURL
    guard directory.deletingLastPathComponent()==updates,staged.path.hasPrefix(directory.path+"/"),target.pathExtension=="app",target.resolvingSymlinksInPath()==target else{throw InstallerError("安装路径不符合要求")}
    // Wait for normal native-app termination; never force-kill or touch the game process.
    let deadline=Date().addingTimeInterval(60)
    while kill(parent,0)==0 && Date()<deadline{Thread.sleep(forTimeInterval:0.2)}
    guard kill(parent,0) != 0 else{throw InstallerError("助手未能正常退出，未替换应用，请手动重试")}
    do{try install(target:target,staged:staged,version:args[5]);result("success","已更新到 \(args[5])，设置和任务已保留")}
    catch{result("failure",error.localizedDescription);try? run("/usr/bin/open",[target.path]);exit(1)}
    try run("/usr/bin/open",[target.path])
    try? fm.removeItem(at:directory)
}catch{
    fputs(error.localizedDescription+"\n",stderr)
    if CommandLine.arguments.dropFirst().first=="install"{result("failure",error.localizedDescription)}
    exit(1)
}
