import Foundation
import SwiftUI
import AppKit
import CoreGraphics

@MainActor final class AppModel:ObservableObject {
    static let shared=AppModel()
    @Published private var recoveryPolicy:RecoveryPolicy = {
        guard let data=UserDefaults.standard.data(forKey:"recoveryPolicy"),let state=try? JSONDecoder().decode(RecoveryPolicy.self,from:data) else{return RecoveryPolicy()}
        return state
    }()
    var recoveryLocked:Bool {recoveryPolicy.locked}
    @Published var autoReconnect=UserDefaults.standard.object(forKey:"autoReconnect") as? Bool ?? true {didSet{UserDefaults.standard.set(autoReconnect,forKey:"autoReconnect")}}
    @Published var redPacketEnabled=UserDefaults.standard.object(forKey:"redPacketEnabled") as? Bool ?? true {didSet{UserDefaults.standard.set(redPacketEnabled,forKey:"redPacketEnabled");Task{[weak self] in guard let self,self.connected,!self.working else{return};await self.pollAssistance()}}}
    @Published var replacedConfirmEnabled=UserDefaults.standard.object(forKey:"replacedConfirmEnabled") as? Bool ?? true {didSet{UserDefaults.standard.set(replacedConfirmEnabled,forKey:"replacedConfirmEnabled")}}
    @Published var areaBossEnabled=UserDefaults.standard.object(forKey:"areaBossEnabled") as? Bool ?? true {didSet{UserDefaults.standard.set(areaBossEnabled,forKey:"areaBossEnabled")}}
    @Published var areaBossBoxEnabled=UserDefaults.standard.object(forKey:"areaBossBoxEnabled") as? Bool ?? true {didSet{UserDefaults.standard.set(areaBossBoxEnabled,forKey:"areaBossBoxEnabled")}}
    private var lastAreaBossKey:AreaBossKey?
    @Published var blankCloseEnabled=(UserDefaults.standard.object(forKey:"blankCloseEnabled") as? Bool ?? UserDefaults.standard.object(forKey:"rewardNoticeEnabled") as? Bool) ?? true {didSet{UserDefaults.standard.set(blankCloseEnabled,forKey:"blankCloseEnabled")}}
    @Published var idleRewardEnabled=UserDefaults.standard.object(forKey:"idleRewardEnabled") as? Bool ?? true {didSet{UserDefaults.standard.set(idleRewardEnabled,forKey:"idleRewardEnabled")}}
    @Published var popupOnlyWhileHunting=UserDefaults.standard.object(forKey:"popupOnlyWhileHunting") as? Bool ?? true {didSet{UserDefaults.standard.set(popupOnlyWhileHunting,forKey:"popupOnlyWhileHunting")}}
    @Published private(set) var popupHandlingAvailable=false
    @Published var assistMessage="连接恢复与红包监控等待游戏连接"
    private var assistTask:Task<Void,Never>?
    private var assistClaimed:[String:Int]=[:]
    private var assistConfirmed:[String:Int]=[:]
    private var assistNoKeyExits:[String:Int]=[:]
    @Published private(set) var packetLedger=RedPacketLedger()
    @Published private(set) var eventHistory:[EventRecord]=[]
    @Published private(set) var popupHistory:[PopupRecord]=[]
    @Published private(set) var popupRecordingActive=false
    private var popupAcks:[String:Int]=[:]
    private var popupSeen=Set<String>()
    private var assistUnsupportedLogged=false
    @Published var connected=false
    @Published var working=false
    @Published private var continuity=HuntContinuity()
    var running:Bool {continuity.requested}
    private var progress=HuntProgress()
    @Published var huntPaused=false
    private var huntArmed=false
    @Published var snapshot:Snapshot?
    @Published var regions:[Region]=[]
    @Published var selectedArea:Int?
    @Published var activities:[Activity]=[]
    @Published var message="正在启动本地连接服务…"
    @Published var errorText:String?
    @Published var currentTarget:String?
    @Published var verified=0
    @Published var injected=false
    @Published private(set) var cacheMessage="正在识别游戏版本…"
    @Published var keyboardEnabled=false
    @Published private var keyboardActive=false
    @Published var keyboardWorking=false
    @Published var keyboardInputAllowed=false
    @Published var lastDetected:Date?
    let bridge:Bridge
    let injector:Injector
    let support:URL
    var catalog:[CatalogBoss]=[]
    private var recoveryWait:Task<Void,Never>?
    private var huntTask:Task<Void,Never>?
    private var keyboardSendTask:Task<Void,Never>?
    private var pendingKeyboardKeys:[Int]?
    private var backgroundActivity:NSObjectProtocol?
    private var monitor:Task<Void,Never>?
    private var generation=0
    private var stopPending=false
    private var refreshTime=Date.distantPast
    private var keyboardController:KeyboardController?
    private var lastEscapeAt:Double=0
    private var keyboardPreferred=UserDefaults.standard.object(forKey:"keyboardPreferred") as? Bool ?? true
    private var connectionGeneration=0
    private var savedHuntArea=UserDefaults.standard.object(forKey:"continuousHuntArea") as? Int
    init(){
        support=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant")
        try? FileManager.default.createDirectory(at:support,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let settings=support.appendingPathComponent("Connection.json")
        let saved=(try? Data(contentsOf:settings)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
        let token=saved?["token"] as? String ?? UUID().uuidString+UUID().uuidString
        bridge=Bridge(token:token);injector=Injector(support:support)
        if let data=try? Data(contentsOf:support.appendingPathComponent("红包记录.json")),let saved=try? JSONDecoder().decode(RedPacketLedger.self,from:data){packetLedger=saved}
        if !FileManager.default.fileExists(atPath:support.appendingPathComponent("红包记录.txt").path){try? packetLedger.readable().write(to:support.appendingPathComponent("红包记录.txt"),atomically:true,encoding:.utf8)}
        if let raw=try? String(contentsOf:support.appendingPathComponent("弹窗历史.jsonl"),encoding:.utf8){
            popupHistory=raw.split(separator:"\n").suffix(2000).compactMap{try? JSONDecoder().decode(PopupRecord.self,from:Data($0.utf8))}.reversed()
            popupSeen=Set(popupHistory.map(\.eventId))
        }
        if let raw=UserDefaults.standard.dictionary(forKey:"popupAcks") as? [String:Int]{popupAcks=raw}
        let eventFile=support.appendingPathComponent("Events.jsonl")
        if let raw=try? String(contentsOf:eventFile,encoding:.utf8) {
            eventHistory=raw.split(separator:"\n").suffix(3000).compactMap{try? JSONDecoder().decode(EventRecord.self,from:Data($0.utf8))}.reversed()
        } else if let raw=try? String(contentsOf:support.appendingPathComponent("Activity.log"),encoding:.utf8) {
            let formatter=ISO8601DateFormatter()
            eventHistory=raw.split(separator:"\n").suffix(500).compactMap { line in
                guard let split=line.firstIndex(of:" "),let date=formatter.date(from:String(line[..<split])) else{return nil}
                let text=String(line[line.index(after:split)...])
                return EventRecord(time:date,category:EventRecord.category(for:text),title:text,data:["来源":"旧版运行记录"])
            }.reversed()
            let lines=eventHistory.reversed().compactMap{try? JSONEncoder().encode($0)}.map{String(decoding:$0,as:UTF8.self)}.joined(separator:"\n")+"\n"
            try? lines.write(to:eventFile,atomically:true,encoding:.utf8)
        }
        if let data=try? Data(contentsOf:support.appendingPathComponent("BOSS钥匙记录.json")){lastAreaBossKey=try? JSONDecoder().decode(AreaBossKey.self,from:data)}
        keyboardEnabled=keyboardPreferred
        if let url=Bundle.main.url(forResource:"Catalog",withExtension:"json"),let data=try? Data(contentsOf:url){catalog=(try? JSONDecoder().decode([CatalogBoss].self,from:data)) ?? []}
        if let url=Bundle.main.url(forResource:"Regions",withExtension:"json"),let data=try? Data(contentsOf:url){regions=(try? JSONDecoder().decode([Region].self,from:data)) ?? []}
        injected=injector.installed
        cacheMessage=injector.cacheDescription
        bridge.onReady={ [weak self] port in
            guard let self else{return}
            let data=try? JSONSerialization.data(withJSONObject:["token":token,"port":Int(port)])
            try? data?.write(to:settings,options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:settings.path)
            self.message="请注入脚本，或等待游戏重新连接"
        }
        bridge.onChange={ [weak self] state in
            guard let self else{return};self.connected=state
            self.connectionGeneration+=1
            let connection=self.connectionGeneration
            if state {
                self.injected=true
                self.log("游戏已连接");self.message="等待游戏角色就绪…"
                Task {
                    for _ in 0..<25 {
                        guard self.connected,self.connectionGeneration==connection else{return}
                        do {try await self.readSnapshot();if self.stopPending && !self.running{_=try await self.bridge.request("stop");self.stopPending=false};await self.detect();return}
                        catch {try? await Task.sleep(nanoseconds:1_000_000_000)}
                    }
                    self.message="已连接，请进入角色后点击重新检测"
                }
            }
            else {
                self.keyboardActive=false
                self.keyboardController?.enabled=false
                self.snapshot=nil
                self.lastDetected=nil
                self.popupHandlingAvailable=false
                self.popupRecordingActive=false
                self.pendingKeyboardKeys=nil
                self.assistMessage="游戏未连接 · 自动重连、红包与弹窗处理等待连接"
                self.cacheMessage=self.injector.cacheDescription
                self.injected=self.injector.installed
                self.message="游戏连接已断开"
                if self.running {self.continuity.manualInput(pressed:false,now:ProcessInfo.processInfo.systemUptime);self.continuity.pause(.connection,now:ProcessInfo.processInfo.systemUptime);self.huntPaused=true;self.huntArmed=false;self.currentTarget=nil;self.message="游戏连接中断，任务保持；每3秒检测，60秒后尝试恢复";self.log(self.message)}
            }
        }
        bridge.onError={ [weak self] text in self?.message="本地连接服务异常";self?.errorText=text }
        let preferred=UInt16(saved?["port"] as? Int ?? 56783)
        do{try bridge.start(port:preferred)}catch{message="本地服务启动失败";errorText=error.localizedDescription}
        keyboardController=KeyboardController{[weak self] keys in self?.queueKeyboard(keys)}
        keyboardController?.onAccessChange={ [weak self] allowed in self?.keyboardInputAllowed=allowed }
        assistTask=Task { [weak self] in
            while !Task.isCancelled {
                guard let self else{return}
                if self.connected && !self.working {await self.pollAssistance()}
                try? await Task.sleep(nanoseconds:500_000_000)
            }
        }
        monitor=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds:3_000_000_000)
                guard let self else{return}
                if !self.connected && !self.working {
                    let description=self.injector.cacheDescription
                    if description != self.cacheMessage {self.cacheMessage=description;self.injected=self.injector.installed}
                }
                if self.connected && !self.working && !self.running {
                    do {
                        let needsDetection=self.snapshot == nil
                        try await self.readSnapshot()
                        if needsDetection {await self.detect()}
                    } catch {}
                }
            }
        }
    }
    private func saveRecoveryPolicy(){if let data=try? JSONEncoder().encode(recoveryPolicy){UserDefaults.standard.set(data,forKey:"recoveryPolicy")}}
    private func recordReplacement(token:String,time:TimeInterval,source:String){
        guard !recoveryLocked,!recoveryPolicy.seen.contains(token) else{return}
        recoveryPolicy.observe(token:token,now:time);saveRecoveryPolicy()
        log("检测到异地登录 · 60秒内第\(recoveryPolicy.hits.count)次",category:"账号保护",data:["错误码":"200104","来源":source,"时间窗口":"60秒","窗口内次数":String(recoveryPolicy.hits.count),"是否锁定":recoveryLocked ? "是" : "否"])
    }
    private func recordPopups(_ status:AssistStatus){
        popupRecordingActive=status.popupEvents != nil
        guard let session=status.popupSession,let events=status.popupEvents else{return}
        for record in events {
            if !popupSeen.contains(record.eventId) {
                guard var encoded=try? JSONEncoder().encode(record) else{continue}
                encoded.append(10)
                let url=support.appendingPathComponent("弹窗历史.jsonl")
                do {
                    if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600])}
                    let file=try FileHandle(forWritingTo:url);defer{try? file.close()}
                    _ = try file.seekToEnd();try file.write(contentsOf:encoded);try file.synchronize()
                } catch {assistMessage="弹窗记录写入失败，将继续重试";break}
                popupSeen.insert(record.eventId);popupHistory.insert(record,at:0)
                if popupHistory.count>2000{popupHistory.removeLast(popupHistory.count-2000)}
                log("弹窗\(record.phaseName)：\(record.title) [\(record.viewId)]",category:"弹窗",data:["组件编号":String(record.viewId),"组件名称":record.viewName,"阶段":record.phaseName,"标题":record.title,"正文":record.body,"弹窗实例":record.occurrenceId,"历史事件ID":record.eventId,"数据文件":"弹窗历史.jsonl"])
            }
            popupAcks[session]=max(popupAcks[session] ?? 0,record.sequence)
        }
        if popupAcks.count>8{popupAcks=[session:popupAcks[session] ?? 0]}
        UserDefaults.standard.set(popupAcks,forKey:"popupAcks")
    }
    private func pollAssistance()async {
        let connection=connectionGeneration
        do {
            let data=try await bridge.request("assistStatus")
            guard connected,!working,connectionGeneration==connection else{return}
            let status=try JSONDecoder().decode(AssistStatus.self,from:data)
            recordPopups(status)
            popupHandlingAvailable=(status.popupHandlingVersion ?? 0)>=2
            let wasLocked=recoveryLocked
            for event in status.replacedEvents {
                let now=Date().timeIntervalSince1970
                if abs(now-event.time/1000)<120 {recordReplacement(token:event.token,time:event.time/1000,source:"游戏登录事件")}
            }
            if let dialog=status.dialog,dialog.kind=="replaced" {
                recordReplacement(token:dialog.token,time:Date().timeIntervalSince1970,source:"异地登录提示")
            }
            saveRecoveryPolicy()
            if !wasLocked && recoveryLocked {log("60秒内第2次异地登录：暂停自动攻击与自动重连，等待手动继续",category:"账号保护",data:["时间窗口":"60秒","触发阈值":"2次","自动攻击":"暂停","自动重连":"暂停","恢复方式":"手动继续"])}
            var fields:[String:Any]=["locked":recoveryLocked,"redPackets":redPacketEnabled,"fastRedPackets":true,"idleReward":idleRewardEnabled && (!popupOnlyWhileHunting || running),"blankClose":blankCloseEnabled && (!popupOnlyWhileHunting || running),"areaBossBox":areaBossBoxEnabled && running && !huntPaused,"huntArea":continuity.area ?? 0,"avoidNoKeyBoss":running && continuity.reason != .manual && continuity.reason != .away]
            if let session=status.popupSession {fields["popupAck"]=popupAcks[session] ?? 0}
            if !recoveryLocked,let dialog=status.dialog,dialog.canConfirm,((dialog.kind=="network" && autoReconnect) || (dialog.kind=="replaced" && replacedConfirmEnabled)){fields["confirmToken"]=dialog.token}
            let result=try await bridge.request("assistRun",fields:fields)
            guard connected,connectionGeneration==connection else{return}
            let updated=try JSONDecoder().decode(AssistStatus.self,from:result)
            recordPopups(updated)
            if let exits=updated.noKeyBossExits,exits>(assistNoKeyExits[updated.session] ?? 0) {log("区域BOSS钥匙已用完，已关闭区域战斗并返回普通首领区域",category:"攻略",data:["钥匙数量":"0","攻略任务":"保留","后续":"继续普通首领巡检"])}
            if let exits=updated.noKeyBossExits {assistNoKeyExits=[updated.session:exits]}
            let changes=packetLedger.merge(updated.packets ?? [])
            if !changes.isEmpty {
                if let data=try? JSONEncoder().encode(packetLedger){try? data.write(to:support.appendingPathComponent("红包记录.json"),options:.atomic)}
                try? packetLedger.readable().write(to:support.appendingPathComponent("红包记录.txt"),atomically:true,encoding:.utf8)
                for packet in changes {
                    let amount=packet.confirmed ? " · 本角色领到 \(packet.myAmount ?? 0) \(packet.moneyName)" : ""
                    log("红包记录：\(packet.channelName) · \(packet.name ?? "聊天红包") · \(packet.result)\(amount)",category:"红包",data:["红包ID":packet.id,"频道":packet.channelName,"类型":packet.name ?? "聊天红包","处理状态":packet.result,"已发出领取请求":packet.attempted ? "是" : "否","服务器已核验":packet.confirmed ? "是" : "否","本角色领取金额":packet.myAmount.map{String($0)} ?? "待核验","货币":packet.moneyName,"红包总额":packet.totalMoney.map{String($0)} ?? "未知","总份数":packet.totalNum.map{String($0)} ?? "未知","剩余份数":packet.remainingNum.map{String($0)} ?? "未知","发现到请求毫秒":packet.requestDelayMs.map{String(Int($0))} ?? "尚未请求"])
                }
            }
            let priorConfirmed=assistConfirmed[updated.session] ?? 0
            if updated.confirmations>priorConfirmed {log("已通过游戏原有确认按钮触发登录重试",category:"连接",data:["本次会话自动确认次数":String(updated.confirmations),"动作":"调用原有确认按钮","结果":"已触发重试，等待连接与角色恢复"])}
            assistConfirmed[updated.session]=updated.confirmations
            let previous=assistClaimed[updated.session] ?? 0
            if updated.claimed>previous {log("已核验领取聊天红包 \(updated.claimed-previous) 个（世界/联盟）")}
            assistClaimed[updated.session]=updated.claimed
            if assistClaimed.count>10 {assistClaimed=[updated.session:updated.claimed]}
            if recoveryLocked {
                assistMessage="异地登录频繁 · 自动重连与攻击已暂停，请手动继续"
                await pauseHunt(.account,text:assistMessage)
            } else {
                assistMessage="\(autoReconnect ? "自动重连已开启" : "自动重连已关闭") · \(redPacketEnabled ? "世界/联盟红包监控中 · 待核验 \(updated.queued) 个" : "红包监控已关闭")"
            }
            assistUnsupportedLogged=false
        } catch {
            guard connected,connectionGeneration==connection else{return}
            if error.localizedDescription=="unsupported_operation" {
                assistMessage="当前游戏脚本需更新，重连确认与红包监控尚未启用"
                if !assistUnsupportedLogged {log(assistMessage);assistUnsupportedLogged=true}
            } else {assistMessage=recoveryLocked ? "异地登录保护保持，等待手动继续" : "连接恢复与红包监控等待游戏响应"}
        }
    }
    func unlockRecovery(){
        recoveryPolicy.unlock();saveRecoveryPolicy()
        assistMessage="已手动解除异地登录保护，正在重新检测"
        log(assistMessage);recoveryWait?.cancel()
        Task{await pollAssistance()}
    }
    var areaName:String {snapshot?.areaName ?? regions.first{$0.id==snapshot?.areaId}?.name ?? "等待检测"}
    var keyboardDescription:String {
        if !keyboardEnabled{return "键盘控制已关闭"}
        if !connected{return "方向键 / WASD / ESC 等待游戏连接"}
        if !keyboardInputAllowed{return "键盘控制等待输入监控授权"}
        return keyboardActive ? "方向键 / WASD / ESC 已开启" : "键盘控制等待游戏就绪"
    }
    var assistanceDescription:String {
        connected ? assistMessage : (recoveryLocked ? "异地登录保护保持 · 游戏未连接，辅助功能等待连接" : "游戏未连接 · 自动重连、红包与弹窗处理等待连接")
    }
    var hasFreshSnapshot:Bool {connected && lastDetected.map{Date().timeIntervalSince($0)<10} == true}
    var rows:[Boss] {
        let area=selectedArea ?? snapshot?.areaId
        if area==snapshot?.areaId && hasFreshSnapshot {return snapshot?.rows ?? []}
        return catalog.filter{$0.area_id==area && [2,3].contains($0.point_type)}.map(\.boss)
    }
    var isCurrentArea:Bool {selectedArea==nil || selectedArea==snapshot?.areaId}
    var canStart:Bool {connected && !working && !running && isCurrentArea && (snapshot?.areaId ?? 0)>0 && snapshot?.location != nil && (snapshot?.runtimeVersion ?? 0)>=3}
    var locationDescription:String {
        if !hasFreshSnapshot {return "角色未就绪或数据已过期 · 列表等待重新检测"}
        guard let location=snapshot?.location else{return connected ? "需重新注入以启用当前位置检测" : "等待游戏连接"}
        let coordinate=location.heroPos.map{String(format:" · 坐标 %.0f, %.0f",$0.x,$0.z)} ?? ""
        return "当前位置：\(location.name)" + (location.kind == "dungeon" ? " · 副本中" : "") + coordinate
    }
    func fieldName(_ boss:Boss)->String {catalog.first{$0.instance_id==boss.insId && $0.point_id==boss.pointId}?.field_name ?? "地图 \(boss.insId)"}
    func log(_ text:String,category:String?=nil,data:[String:String]=[:]) {
        activities.insert(Activity(text:text),at:0);if activities.count>150{activities.removeLast()}
        let event=EventRecord(time:Date(),category:category ?? EventRecord.category(for:text),title:text,data:data)
        eventHistory.insert(event,at:0);if eventHistory.count>3000{eventHistory.removeLast(eventHistory.count-3000)}
        let formatter=ISO8601DateFormatter();formatter.timeZone=TimeZone.current
        let line="\(formatter.string(from:event.time)) \(text)\n"
        appendLog(Data(line.utf8),to:support.appendingPathComponent("Activity.log"))
        if var encoded=try? JSONEncoder().encode(event){encoded.append(10);appendLog(encoded,to:support.appendingPathComponent("Events.jsonl"))}
    }
    private func appendLog(_ data:Data,to url:URL){
        if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600])}
        if let file=try? FileHandle(forWritingTo:url){_ = try? file.seekToEnd();try? file.write(contentsOf:data);try? file.close()}
    }
    func readSnapshot()async throws {
        let connection=connectionGeneration
        let data=try await bridge.request("list");let value=try JSONDecoder().decode(Snapshot.self,from:data)
        guard connected,connectionGeneration==connection else{throw BridgeFailure(message:"游戏连接已更新，等待重新检测")}
        keyboardActive=value.keyboard?.enabled ?? false
        keyboardController?.enabled=keyboardActive && keyboardPreferred
        if FileManager.default.fileExists(atPath:support.appendingPathComponent("KeyboardProbe.enabled").path) {
            try? data.write(to:support.appendingPathComponent("KeyboardProbe.json"),options:.atomic)
        }
        progress.observe(value,now:ProcessInfo.processInfo.systemUptime)
        if let key=value.areaBossKey,key != lastAreaBossKey {
            log("区域BOSS钥匙：\(key.count) / \(key.limit.map{String($0)} ?? "—")",category:"攻略",data:["钥匙物品编号":String(key.itemId),"当前数量":String(key.count),"此前数量":lastAreaBossKey.map{String($0.count)} ?? "首次检测"])
            if let encoded=try? JSONEncoder().encode(key){try? encoded.write(to:support.appendingPathComponent("BOSS钥匙记录.json"),options:.atomic)}
            lastAreaBossKey=key
        }
        snapshot=value
        if let script=value.scriptIdentity {cacheMessage="游戏已连接 · \(script)"}
        if let values=value.areas {regions=values}
        if selectedArea==nil {selectedArea=value.areaId}
        lastDetected=Date()
        if !running,let area=savedHuntArea {savedHuntArea=nil;beginHunt(area:area)}
        if keyboardPreferred && !keyboardActive && !keyboardWorking {
            await setKeyboard(true,remember:false)
        }
    }
    func setKeyboard(_ enabled:Bool,remember:Bool=true)async {
        guard connected,!keyboardWorking else{return}
        keyboardWorking=true;defer{keyboardWorking=false}
        do {
            if !enabled {continuity.manualInput(pressed:false,now:ProcessInfo.processInfo.systemUptime)}
            let data=try await bridge.request("keyboardMode",fields:["enabled":enabled,"preserveNavigation":true])
            let state=try JSONDecoder().decode(KeyboardStatus.self,from:data)
            if remember {keyboardPreferred=enabled;keyboardEnabled=enabled;UserDefaults.standard.set(enabled,forKey:"keyboardPreferred")}
            keyboardActive=state.enabled
            keyboardController?.enabled=state.enabled && keyboardPreferred
            message=state.enabled ? "方向键 / WASD 已开启，请切回游戏窗口" : "方向键 / WASD 已关闭"
            log(message)
        }catch{errorText="方向键设置失败：\(error.localizedDescription)。旧版脚本需要重新注入。"}
    }
    func detect()async {
        guard connected,!working else{return};working=true;defer{working=false}
        do{
            _=try await bridge.request("refresh");try await Task.sleep(nanoseconds:600_000_000)
            try await readSnapshot();selectedArea=snapshot?.areaId;refreshTime=Date()
            message="已检测 \(areaName) · \(snapshot?.rows.count ?? 0) 个首领"
            log(message)
        }catch{errorText=error.localizedDescription;message="检测未完成"}
    }
    func inject()async {
        guard !working,bridge.port != 0 else{return};working=true;defer{working=false}
        if running {await pauseHunt(.maintenance,text:"正在更新脚本，任务保持，完成后自动恢复")}
        do{message="正在识别当前版本并备份注入…";try await injector.inject(port:bridge.port,token:bridge.token);injected=true;cacheMessage=injector.cacheDescription;message="脚本已写入，等待游戏连接验证";log("当前版本脚本已写入，原始缓存已分版本备份；游戏已重启，等待连接验证")}
        catch{message="注入未完成";errorText=error.localizedDescription}
    }
    func restore()async {
        guard !working else{return};working=true;defer{working=false};if running {await pauseHunt(.maintenance,text:"正在还原脚本，任务保持，等待可用连接")}
        do{try await injector.restore();injected=false;message="已还原原始脚本";log("原始缓存已还原，游戏已重启")}
        catch{errorText=error.localizedDescription}
    }
    private func queueKeyboard(_ keys:[Int]) {
        guard connected,keyboardActive,keyboardPreferred else{return}
        pendingKeyboardKeys=keys
        guard keyboardSendTask==nil else{return}
        let connection=connectionGeneration
        keyboardSendTask=Task { [weak self] in
            guard let self else{return}
            defer{self.keyboardSendTask=nil}
            while let keys=self.pendingKeyboardKeys {
                self.pendingKeyboardKeys=nil
                guard self.connected,self.connectionGeneration==connection,self.keyboardActive,self.keyboardPreferred else{return}
                do {
                    let data=try await self.bridge.request("keyboardKeys",fields:["keys":keys])
                    guard self.connectionGeneration==connection else{return}
                    let status=try JSONDecoder().decode(KeyboardStatus.self,from:data)
                    if let result=status.escape,result.at != self.lastEscapeAt {
                        self.lastEscapeAt=result.at
                        self.log(result.closed ? "ESC：已触发页面返回（\(result.viewId ?? 0)）" : "ESC：未执行返回（\(result.reason ?? "未知")，页面\(result.viewId ?? 0)）")
                    }
                    let pressed = !(status.pressed ?? []).isEmpty
                    let wasHeld=self.continuity.movementHeld
                    if self.running,(!pressed && wasHeld) || ([1,5].contains(status.sceneType ?? -1) && self.snapshot?.areaId==self.continuity.area) {
                        self.continuity.manualInput(pressed:pressed,now:ProcessInfo.processInfo.systemUptime)
                        if pressed || wasHeld {
                            await self.pauseHunt(.manual,text:"手动移动中；松键60秒后自动恢复攻略",restartDelay:false)
                        }
                    }
                }catch{
                    guard self.connectionGeneration==connection else{return}
                    self.keyboardActive=false;self.keyboardController?.enabled=false
                    self.continuity.manualInput(pressed:false,now:ProcessInfo.processInfo.systemUptime)
                    self.log("按键连接暂不可用，保留开启设置，检测恢复后自动重试")
                }
            }
        }
    }
    private func pauseHunt(_ reason:HuntContinuity.PauseReason,text:String,restartDelay:Bool=false)async {
        guard running else{return}
        let wasArmed=huntArmed
        let changed=continuity.reason != reason || !huntPaused
        continuity.pause(reason,now:ProcessInfo.processInfo.systemUptime,restartDelay:restartDelay)
        huntPaused=true;huntArmed=false;currentTarget=nil;message=text
        if changed {log(text)}
        if wasArmed && connected {
            _ = try? await bridge.request("suspendHunt")
        }
    }
    var canResumeHunt:Bool {running && huntPaused && !working}
    func resumeHunt(){
        guard canResumeHunt else{return}
        if recoveryLocked {unlockRecovery()}
        guard continuity.requestResume() else{message="请先松开方向键 / WASD，再点立即继续";return}
        message="正在重新检测场景并继续攻略…"
        log("手动立即继续：跳过恢复倒计时，重新核对场景")
        recoveryWait?.cancel()
    }
    private func waitForRecovery()async {
        let wait=Task<Void,Never> {try? await Task.sleep(nanoseconds:3_000_000_000)}
        recoveryWait=wait
        await wait.value
        recoveryWait=nil
    }
    func prepareForExit()async {
        assistTask?.cancel()
        // Keep the saved task for permission-driven relaunch and app updates.
        generation+=1;huntTask?.cancel();recoveryWait?.cancel()
        if connected {_ = try? await bridge.request("suspendHunt")}
    }
    private func isHunting(_ run:Int)->Bool {running && run==generation && !Task.isCancelled}
    private func waitForHuntArea(_ area:Int,run:Int)async throws {
        while isHunting(run) {
            if working {
                await waitForRecovery();continue
            }
            if recoveryLocked {
                await pauseHunt(.account,text:"异地登录频繁 · 任务保留，需手动立即继续")
                await waitForRecovery();continue
            }
            try await readSnapshot();try Task.checkCancellation()
            guard isHunting(run),let current=snapshot else{throw CancellationError()}
            switch HuntLocationGate.evaluate(current,area:area) {
            case .unsupported:
                throw BridgeFailure(message:"等待支持副本检测的脚本连接")
            case .away:
                let name=regions.first{$0.id==area}?.name ?? "原区域"
                await pauseHunt(.away,text:"\(current.location?.name ?? "其他场景")中 · 任务保持，等待返回\(name)")
            case .transition:
                await pauseHunt(.unavailable,text:"场景加载中 · 任务保持，每3秒检测，60秒后尝试恢复")
            case .ready:
                if progress.stalled(now:ProcessInfo.processInfo.systemUptime) {
                    await pauseHunt(.stalled,text:"游戏画面暂未推进 · 任务保持，每3秒检测，等待恢复后继续")
                } else if continuity.canResume(now:ProcessInfo.processInfo.systemUptime) {
                    if !huntArmed {
                        _=try await bridge.request("refresh")
                        try await Task.sleep(nanoseconds:600_000_000)
                        try await readSnapshot();try Task.checkCancellation()
                        guard isHunting(run),let latest=snapshot else{throw CancellationError()}
                        guard !working,!recoveryLocked,continuity.canResume(now:ProcessInfo.processInfo.systemUptime),HuntLocationGate.evaluate(latest,area:area) == .ready else{continue}
                        do {_=try await bridge.request("attackMode",fields:["areaId":area])}
                        catch {if error.localizedDescription == "hunt_scene_unavailable" {continue};throw error}
                        guard isHunting(run) else{throw CancellationError()}
                        guard !working,!recoveryLocked,continuity.canResume(now:ProcessInfo.processInfo.systemUptime) else{continue}
                        huntArmed=true;refreshTime=Date()
                        if huntPaused {log("角色与场景已就绪，重新检测并自动继续\(areaName)攻略")}
                        continuity.resumed();huntPaused=false;message="自动攻略中"
                    }
                    return
                } else {
                    let remaining=continuity.remaining(now:ProcessInfo.processInfo.systemUptime)
                    message=continuity.movementHeld ? "手动移动中 · 任务保持，松键60秒后自动继续" : "任务保持 · 每3秒检测，\(remaining)秒后尝试恢复攻略"
                }
            }
            await waitForRecovery()
        }
        throw CancellationError()
    }
    private func startBackgroundActivity(){
        if backgroundActivity==nil {
            backgroundActivity=ProcessInfo.processInfo.beginActivity(options:[.userInitiated,.automaticTerminationDisabled],reason:"用户正在自动攻略首领，保持后台运行")
        }
    }

    func startAttack(){
        guard canStart,let area=snapshot?.areaId else{return}
        beginHunt(area:area)
    }
    private func beginHunt(area:Int){
        guard !running,area>0 else{return}
        UserDefaults.standard.set(area,forKey:"continuousHuntArea")
        generation+=1;let run=generation;continuity.start(area:area);huntPaused=false;huntArmed=false;stopPending=false;verified=0;currentTarget=nil
        startBackgroundActivity()
        message="自动攻略中";log("启动持续巡检：每3秒检测，异常60秒重试，仅手动停止结束任务")
        huntTask=Task { [weak self] in
            guard let self else{return}
            var retry=HuntRetryPolicy()
            var lastError="";var lastErrorTime=Date.distantPast
            while self.isHunting(run) {
                do{
                    try await self.waitForHuntArea(area,run:run)
                    if Date().timeIntervalSince(self.refreshTime)>15 {
                        _=try await self.bridge.request("refresh");self.refreshTime=Date()
                        try await Task.sleep(nanoseconds:500_000_000)
                        try await self.readSnapshot()
                    }
                    guard self.isHunting(run) else{break}
                    guard let current=self.snapshot else{throw BridgeFailure(message:"等待场景数据恢复")}
                    guard HuntLocationGate.evaluate(current,area:area) == .ready else{continue}
                    guard !self.working,!self.recoveryLocked,self.continuity.canResume(now:ProcessInfo.processInfo.systemUptime),self.huntArmed else{continue}
                    let ready=current.rows.filter{$0.status=="ready" && (!$0.isAreaBoss || (self.areaBossEnabled && ($0.keyCount ?? 0)>0))}
                    let candidates=ready.filter{retry.eligible($0.id,now:ProcessInfo.processInfo.systemUptime)}
                    let target=candidates.first{$0.isAreaBoss} ?? candidates.first{$0.insId==10000+current.fieldId} ?? candidates.first
                    guard let target else{
                        self.currentTarget=nil;self.message=ready.isEmpty ? (current.areaBossKey?.count==0 ? "区域BOSS钥匙已用完 · 等待普通首领刷新" : "等待首领刷新…") : "保持巡检，等待暂缓目标重试…"
                        try await Task.sleep(nanoseconds:3_000_000_000);continue
                    }
                    self.currentTarget=target.name;self.message="正在前往 \(target.name)"
                    do {_=try await self.bridge.request("goto",fields:["areaId":area,"bossId":target.bossId,"insId":target.insId,"pointId":target.pointId])}
                    catch {if error.localizedDescription == "hunt_scene_unavailable" {continue};throw error}
                    self.log("前往 \(self.fieldName(target)) · \(target.name)")
                    var remaining:TimeInterval=target.isAreaBoss ? 600 : 75;var passed=false;var interrupted=false
                    var previousGameTime=current.location?.gameTime
                    while remaining>0 && self.isHunting(run) {
                        let started=ProcessInfo.processInfo.systemUptime
                        try await Task.sleep(nanoseconds:2_000_000_000);try Task.checkCancellation();try await self.readSnapshot()
                        guard self.isHunting(run),let value=self.snapshot else{break}
                        if target.isAreaBoss,value.areaBossKey?.count==0 {
                            self.log("区域BOSS钥匙已用完，取消当前区域BOSS目标，继续普通首领巡检")
                            _=try await self.bridge.request("assistRun",fields:["avoidNoKeyBoss":true,"huntArea":area,"locked":self.recoveryLocked])
                            interrupted=true;self.currentTarget=nil;break
                        }
                        if let route=value.navigation,route.bossId==target.bossId {
                            if route.phase=="blocked" {throw BridgeFailure(message:route.error ?? "游戏未接受寻路")}
                            if route.phase=="attacking" {self.message="已到达 \(target.name) · 自动攻击中"}
                            else if route.phase=="moving" {self.message="正在前往 \(target.name)"}
                        }
                        let gate=HuntLocationGate.evaluate(value,area:area)
                        if self.working || !self.huntArmed || self.continuity.reason != nil || gate == .away {interrupted=true;break}
                        if gate == .transition {previousGameTime=value.location?.gameTime;continue}
                        guard gate == .ready else{throw BridgeFailure(message:"当前脚本不支持位置检测，请重新注入")}
                        if let row=value.rows.first(where:{$0.id==target.id}),row.status=="cooldown",(row.cdSeconds ?? 0)>0 {
                            passed=true;retry.succeeded(target.id);self.verified+=1;self.log("已核验冷却：\(target.name)");break
                        }
                        let elapsed=ProcessInfo.processInfo.systemUptime-started
                        if let before=previousGameTime,let after=value.location?.gameTime {
                            previousGameTime=after
                            if after<=before {
                                if self.progress.stalled(now:ProcessInfo.processInfo.systemUptime) {await self.pauseHunt(.stalled,text:"游戏画面暂未推进 · 保留任务，等待恢复后继续");interrupted=true;break}
                                self.message="游戏暂未推进，保持攻略并等待恢复…";continue
                            }
                            remaining-=min(elapsed,(after-before)/1000)
                        } else {remaining-=elapsed}
                    }
                    guard self.isHunting(run) else{break}
                    if interrupted {self.currentTarget=nil;continue}
                    if !passed {
                        let delay=retry.deferTarget(target.id,now:ProcessInfo.processInfo.systemUptime)
                        self.log("\(target.name)暂未进入冷却，暂缓\(Int(delay))秒；继续巡检其他首领")
                        _=try await self.bridge.request("suspendHunt")
                        self.huntArmed=false;self.currentTarget=nil
                    }
                }catch is CancellationError {break}catch{
                    guard self.isHunting(run) else{break}
                    await self.pauseHunt(self.connected ? .unavailable : .connection,text:self.connected ? "游戏暂未就绪 · 任务保持，每3秒检测，60秒后重试" : "游戏连接中断 · 任务保持，每3秒检测，60秒后重试",restartDelay:true)
                    if lastError != error.localizedDescription || Date().timeIntervalSince(lastErrorTime)>30 {
                        self.log("攻略等待恢复：\(error.localizedDescription)");lastError=error.localizedDescription;lastErrorTime=Date()
                    }
                    do{try await Task.sleep(nanoseconds:3_000_000_000)}catch{break}
                }
            }
        }
    }
    func stopAttack()async {
        savedHuntArea=nil;UserDefaults.standard.removeObject(forKey:"continuousHuntArea")
        generation+=1;continuity.stop();huntPaused=false;huntArmed=false;huntTask?.cancel();huntTask=nil;currentTarget=nil
        if let activity=backgroundActivity {ProcessInfo.processInfo.endActivity(activity);backgroundActivity=nil}
        if connected {
            do{_=try await bridge.request("stop");stopPending=false;message="已停止攻击";log("已取消跟随并关闭自动战斗")}
            catch{stopPending=true;message="已停止派发，等待游戏确认停止";log(message)}
        }else{stopPending=true;message="已停止派发，重连后取消跟随"}
    }
    func requestKeyboardAccess(){
        // Called only by the user's explicit permission button; never on launch.
        if !CGRequestListenEventAccess(),let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    func showLogs(){NSWorkspace.shared.open(support)}
}
