import Foundation
import AppKit
import CryptoKit

final class UpdateDownload:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    private var session:URLSession?
    private var task:URLSessionDownloadTask?
    private var completion:CheckedContinuation<URL,Error>?
    private let destination:URL
    private let progress:@Sendable (Int64,Int64)->Void
    init(destination:URL,progress:@escaping @Sendable (Int64,Int64)->Void){self.destination=destination;self.progress=progress}
    func fetch(_ url:URL)async throws->URL{
        try await withCheckedThrowingContinuation{continuation in
            completion=continuation
            let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=60;config.timeoutIntervalForResource=900
            session=URLSession(configuration:config,delegate:self,delegateQueue:OperationQueue.main)
            task=session!.downloadTask(with:url);task!.resume()
        }
    }
    func cancel(){task?.cancel()}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){progress(totalBytesWritten,totalBytesExpectedToWrite)}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){
        do{
            guard let response=downloadTask.response as? HTTPURLResponse,response.statusCode==200 else{throw UpdateError("下载服务器返回异常，请重试")}
            guard downloadTask.countOfBytesReceived<=250_000_000 else{throw UpdateError("更新包超出大小限制")}
            try FileManager.default.moveItem(at:location,to:destination)
            completion?.resume(returning:destination);completion=nil
        }catch{completion?.resume(throwing:error);completion=nil}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        if let error{completion?.resume(throwing:error);completion=nil}
        session.finishTasksAndInvalidate();self.session=nil;self.task=nil
    }
}
struct UpdateError:LocalizedError {let message:String;init(_ message:String){self.message=message};var errorDescription:String?{message}}

@MainActor final class UpdateController:ObservableObject {
    static let shared=UpdateController()
    @Published var releases:[AppRelease]=[]
    @Published var checking=false
    @Published var installing=false
    @Published var phase="尚未检查更新"
    @Published var error:String?
    @Published var progress:Double=0
    @Published var downloaded:Int64=0
    @Published var total:Int64=0
    @Published var checkedAt:Date?
    @Published var lastInstallMessage:String?
    private var downloader:UpdateDownload?
    private(set) var readyToQuit=false
    let currentVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0"
    init(){
        let result=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant/UpdateResult.json")
        if let data=try? Data(contentsOf:result),let record=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]{lastInstallMessage=record["message"] as? String}
    }
    var latest:AppRelease?{releases.first}
    var available:Bool{guard let latest,let current=AppVersion(currentVersion),let next=AppVersion(latest.version) else{return false};return current<next}
    var pending:[AppRelease]{releases.filter{(AppVersion(currentVersion) ?? AppVersion("0.0.0")!)<AppVersion($0.version)!}}
    var canInstall:Bool{Bundle.main.bundleURL.pathExtension=="app" && FileManager.default.isWritableFile(atPath:Bundle.main.bundleURL.deletingLastPathComponent().path)}
    func check()async{
        guard !checking,!installing else{return};checking=true;error=nil;defer{checking=false}
        do{
            var request=URLRequest(url:URL(string:"https://api.github.com/repos/\(UpdatePolicy.repository)/releases?per_page=30")!);request.timeoutInterval=20
            request.setValue("BossAssistant/\(currentVersion)",forHTTPHeaderField:"User-Agent");request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
            let(data,response)=try await URLSession.shared.data(for:request)
            guard let response=response as? HTTPURLResponse,response.statusCode==200 else{throw UpdateError("暂时无法检查版本，请检查网络后重试")}
            releases=UpdatePolicy.releases(try JSONDecoder().decode([AppRelease].self,from:data));checkedAt=Date()
            phase=available ? "发现新版本 \(latest!.version)" : (latest==nil ? "尚无正式发布版本" : "当前已是最新版本")
        }catch{self.error=error.localizedDescription;phase="检查更新失败"}
    }
    func cancel(){downloader?.cancel()}
    func install()async{
        guard available,!installing,canInstall,let release=latest,let archive=release.archive,let checksum=release.checksum else{return}
        guard UpdatePolicy.allowed(archive.browser_download_url,version:release.version,name:archive.name),UpdatePolicy.allowed(checksum.browser_download_url,version:release.version,name:checksum.name),archive.size>0,archive.size<=250_000_000 else{error="发布文件不符合更新规范";return}
        installing=true;error=nil;progress=0;downloaded=0;total=archive.size;phase="正在下载更新…"
        let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant/Updates/\(UUID().uuidString)")
        var handedOff=false
        defer{downloader=nil;if !handedOff{installing=false;try? FileManager.default.removeItem(at:directory)}}
        do{
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            var request=URLRequest(url:checksum.browser_download_url);request.timeoutInterval=30
            let(data,response)=try await URLSession.shared.data(for:request)
            guard (response as? HTTPURLResponse)?.statusCode==200,data.count<2048,let text=String(data:data,encoding:.utf8),let expected=UpdatePolicy.checksum(text,filename:archive.name) else{throw UpdateError("校验文件无效，未安装更新")}
            let download=UpdateDownload(destination:directory.appendingPathComponent("update.zip")){[weak self] bytes,length in Task{@MainActor in self?.downloaded=bytes;if length>0{self?.total=length};self?.progress=length>0 ? Double(bytes)/Double(length) : 0}}
            downloader=download
            let file=try await download.fetch(archive.browser_download_url)
            guard (try FileManager.default.attributesOfItem(atPath:file.path)[.size] as? NSNumber)?.int64Value==archive.size else{throw UpdateError("更新包大小不匹配，未安装")}
            phase="正在校验安装包与签名…"
            let digest=try await Task.detached{SHA256.hash(data:try Data(contentsOf:file,options:.mappedIfSafe)).map{String(format:"%02x",$0)}.joined()}.value
            guard digest==expected else{throw UpdateError("安装包校验失败，已保留当前版本")}
            guard UpdatePolicy.safeArchive(try Data(contentsOf:file,options:.mappedIfSafe)) else{throw UpdateError("更新包目录结构不安全，未解包或安装")}
            let unpacked=directory.appendingPathComponent("unpacked")
            try await Self.command("/usr/bin/ditto",["-xk",file.path,unpacked.path])
            let staged=unpacked.appendingPathComponent("首领助手.app")
            let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BossAssistantUpdater")
            try await Self.command(helper.path,["verify",staged.path,release.version])
            guard !AppModel.shared.working else{throw UpdateError("游戏脚本正在处理，请完成后再更新助手")}
            phase="校验通过，正在保留任务并重开助手…"
            await AppModel.shared.prepareForExit()
            // Copy the trusted installer out of the bundle before moving the old app.
            let installer=directory.appendingPathComponent("installer")
            try FileManager.default.copyItem(at:helper,to:installer)
            let process=Process();process.executableURL=installer;process.arguments=["install",String(ProcessInfo.processInfo.processIdentifier),Bundle.main.bundleURL.path,staged.path,release.version,directory.path]
            try process.run();handedOff=true
            readyToQuit=true
            NotificationCenter.default.post(name:Notification.Name("BossAssistantInstallReady"),object:nil)
            // SwiftUI settings is a sheet; dismiss before asking AppKit to terminate.
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4){NSApplication.shared.terminate(nil)}
        }catch{self.error=error.localizedDescription;phase=(error as NSError).code == NSURLErrorCancelled ? "已取消下载" : "更新未完成，当前版本保持可用"}
    }
    nonisolated static func command(_ path:String,_ args:[String])async throws{
        try await Task.detached{
            let task=Process();task.executableURL=URL(fileURLWithPath:path);task.arguments=args
            let pipe=Pipe();task.standardOutput=pipe;task.standardError=pipe;try task.run()
            let output=pipe.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
            guard task.terminationStatus==0 else{throw UpdateError(String(data:output,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines).suffix(600).description ?? "更新校验失败")}
        }.value
    }
}
