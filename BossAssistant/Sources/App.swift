import SwiftUI
import AppKit

struct MainView:View {
    @ObservedObject var model:AppModel
    @State private var showInject=false
    @State private var showRestore=false
    @State private var showEvents=false
    @State private var showSettings=false
    @State private var bossPage=0
    private var pageCount:Int {max(1,(model.rows.count+19)/20)}
    private var pageRows:[Boss] {Array(model.rows.dropFirst(min(bossPage,pageCount-1)*20).prefix(20))}
    private let teal=Color(red:0.23,green:0.84,blue:0.75)
    var body:some View{
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:10){Image(systemName:"scope").font(.system(size:27,weight:.semibold)).foregroundStyle(teal);VStack(alignment:.leading,spacing:3){Text("首领助手").font(.headline);Text("勇者联盟").font(.caption).foregroundStyle(.secondary)}}.padding(22)
                HStack(spacing:7){Circle().fill(model.connected ? teal : Color.orange).frame(width:7,height:7);Text(model.connected ? "游戏已连接" : "等待游戏连接").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,24).padding(.bottom,22)
                Text("全部区域").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.horizontal,24).padding(.bottom,10)
                ScrollView{VStack(spacing:3){ForEach(model.regions){region in
                    Button{model.selectedArea=region.id} label:{HStack(spacing:9){Image(systemName:region.id==model.snapshot?.areaId ? "location.fill" : region.unlocked==false ? "lock" : "map").font(.system(size:12)).foregroundStyle(region.id==model.snapshot?.areaId ? teal : .secondary);Text(region.name).font(.system(size:13));Spacer();if region.id==model.snapshot?.areaId{Text("当前").font(.system(size:10,weight:.medium)).foregroundStyle(teal)}}.padding(.horizontal,12).padding(.vertical,10).background(model.selectedArea==region.id ? teal.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("区域：\(region.name)")
                }}.padding(.horizontal,12)}
                Divider().overlay(Color.white.opacity(0.05)).padding(.top,12)
                VStack(alignment:.leading,spacing:14){
                    Button{Task{await model.openGame()}} label:{Label("打开游戏",systemImage:"play.rectangle")}.disabled(model.working)
                    Button{Task{await model.restartGame()}} label:{Label("重启游戏",systemImage:"arrow.clockwise")}.disabled(model.working)
                    Button{showInject=true} label:{Label(model.injected ? "重新注入脚本" : "注入脚本",systemImage:"puzzlepiece.extension")}.disabled(model.working)
                    Button{showRestore=true} label:{Label("还原原始脚本",systemImage:"arrow.uturn.backward")}.disabled(model.working || !model.injected)
                    Button{NearbyTargetPanel.present(model:model)} label:{Label("附近怪物 / 集火",systemImage:"scope")}
                    Button{showSettings=true} label:{Label("设置",systemImage:"gearshape")}
                    Button{showEvents=true} label:{Label("事件记录",systemImage:"list.bullet.rectangle")}
                }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(.secondary).padding(22)
            }.frame(width:218).background(Color(red:0.075,green:0.09,blue:0.11))
            Rectangle().fill(Color.white.opacity(0.07)).frame(width:1)
            VStack(alignment:.leading,spacing:10){
                HStack(spacing:16){
                    VStack(alignment:.leading,spacing:4){
                        Text(model.isCurrentArea ? model.areaName : model.regions.first{$0.id==model.selectedArea}?.name ?? "区域").font(.system(size:24,weight:.semibold))
                        Label(model.isCurrentArea ? model.locationDescription : "非当前区域 · 仅显示配置",systemImage:"location").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength:4)
                    if model.running {
                        Label(model.restartDescription,systemImage:model.scheduledRestartInProgress ? "arrow.triangle.2.circlepath" : "timer")
                            .font(.system(size:11,weight:.medium,design:.monospaced)).monospacedDigit().foregroundStyle(teal)
                            .padding(9).background(teal.opacity(0.08),in:RoundedRectangle(cornerRadius:8)).help("自动攻略每2小时重启一次游戏")
                    }
                    Button{Task{await model.detect()}}label:{Image(systemName:"arrow.clockwise")}.disabled(!model.connected || model.snapshot == nil || model.working).accessibilityLabel("重新检测首领列表").help("重新检测首领列表")
                }
                BossFilterControls(model:model)
                VStack(alignment:.leading,spacing:0){
                    HStack(spacing:12){
                        Text("首领").font(.system(size:12,weight:.semibold))
                        Text("\(model.rows.count)").font(.caption).foregroundStyle(.secondary)
                        if let key=model.snapshot?.areaBossKey,model.isCurrentArea {Label("\(key.count)/\(key.limit.map{String($0)} ?? "—")",systemImage:"key.fill").font(.system(size:10)).foregroundStyle(.orange).help("区域BOSS钥匙")}
                        Spacer(minLength:0)
                        BossStatusLegend(color:teal,text:"已刷新")
                        BossStatusLegend(color:.orange,text:"冷却")
                        BossStatusLegend(color:.gray,text:"未就绪")
                        if pageCount>1 {
                            Button{bossPage=max(0,bossPage-1)}label:{Image(systemName:"chevron.left")}.disabled(bossPage==0).help("上一页")
                            Text("\(min(bossPage,pageCount-1)+1)/\(pageCount)").monospacedDigit()
                            Button{bossPage=min(pageCount-1,bossPage+1)}label:{Image(systemName:"chevron.right")}.disabled(bossPage>=pageCount-1).help("下一页")
                        }
                    }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,10)
                    ScrollView {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8){
                            ForEach(pageRows){boss in BossTile(model:model,boss:boss)}
                        }.padding(.horizontal,10).padding(.bottom,10)
                        if model.rows.isEmpty {
                            VStack(spacing:10){Image(systemName:"scope").font(.largeTitle);Text("暂无符合条件的首领").font(.callout);Text("选择区域或调整上方筛选").font(.caption)}.foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,32)
                        }
                    }.frame(minHeight:332,maxHeight:.infinity)

                }.background(Color.white.opacity(0.03),in:RoundedRectangle(cornerRadius:14)).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Color.white.opacity(0.06)))
                HStack(spacing:8){
                    Image(systemName:"keyboard").foregroundStyle(model.keyboardEnabled && model.connected ? teal : .gray).help(model.keyboardDescription)
                    Text(model.assistanceDescription).font(.system(size:10)).foregroundStyle(model.recoveryLocked ? Color.orange : .secondary).lineLimit(1).help(model.assistanceDescription)
                    Spacer(minLength:0)
                    if model.recoveryLocked {Button("解除保护"){model.unlockRecovery()}.tint(.orange)}
                }
                if !model.connected {Text(model.cacheMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                HStack(spacing:12){
                    Image(systemName:model.huntPaused ? "pause.circle" : model.running ? "waveform.path" : "checkmark.shield").foregroundStyle(teal)
                    VStack(alignment:.leading,spacing:5){Text(model.message).font(.system(size:13,weight:.medium));Text(model.running ? "本次已核验 \(model.verified) 个 · 每3秒检测 · 异常60秒重试" : "在游戏内直接寻路 · 不占用鼠标和键盘").font(.caption).foregroundStyle(.secondary)}
                    Spacer()
                    if model.running {
                        if model.huntPaused {Button{model.resumeHunt()}label:{Label("立即继续",systemImage:"play.fill").padding(.horizontal,8).padding(.vertical,8)}.buttonStyle(.borderedProminent).tint(teal).foregroundStyle(.black).disabled(!model.canResumeHunt).help("跳过60秒等待；确认回到攻略区域后继续，副本或加载期间保留任务。")}
                        Button{Task{await model.stopAttack()}}label:{Label("停止攻击",systemImage:"stop.fill").padding(.horizontal,14).padding(.vertical,8)}.buttonStyle(.borderedProminent).tint(.red).accessibilityLabel("停止攻击")}
                    else {Button{model.startAttack()}label:{Label("开始自动攻略",systemImage:"play.fill").padding(.horizontal,14).padding(.vertical,8)}.buttonStyle(.borderedProminent).tint(teal).foregroundStyle(.black).disabled(!model.canStart).accessibilityLabel("开始自动攻略")}
                }.padding(10).background(teal.opacity(0.045),in:RoundedRectangle(cornerRadius:14))

            }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(red:0.045,green:0.055,blue:0.075))
        }.frame(minWidth:1020,minHeight:700).preferredColorScheme(.dark).tint(teal)
        .onChange(of:model.selectedArea){bossPage=0}
        .onChange(of:pageCount){bossPage=min(bossPage,pageCount-1)}
        .sheet(isPresented:$showSettings){SettingsView(model:model)}
        .sheet(isPresented:$showEvents){EventHistoryView(model:model)}
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("BossAssistantInstallReady"))){_ in showSettings=false;showEvents=false}
        .alert("注入脚本",isPresented:$showInject){Button("取消",role:.cancel){};Button("备份并注入"){Task{await model.inject()}}}message:{Text("将识别当前热更新版本，分版本备份原始缓存，注入脚本并重启游戏一次。支持游戏 1.16.3 的已适配热更新，未知版本会停止并提示。")}
        .alert("还原原始脚本",isPresented:$showRestore){Button("取消",role:.cancel){};Button("还原并重启"){Task{await model.restore()}}}message:{Text("将暂停派发并保留攻略任务，恢复原始游戏脚本，并重启游戏。")}
        .alert("操作提示",isPresented:Binding(get:{model.errorText != nil},set:{if !$0{model.errorText=nil}})){Button("知道了"){model.errorText=nil}}message:{Text(model.errorText ?? "")}
    }
}
private struct BossStatusLegend:View {
    let color:Color
    let text:String
    var body:some View {HStack(spacing:5){Circle().fill(color).frame(width:6,height:6);Text(text)}}
}

private struct BossTile:View {
    @ObservedObject var model:AppModel
    let boss:Boss
    private let teal=Color(red:0.23,green:0.84,blue:0.75)
    private var active:Bool {model.isCurrentTarget(boss)}
    private var mapLabel:String {
        let full=model.fieldName(boss)
        guard let range=full.range(of:"[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫIVXLCDM]+$",options:.regularExpression) else{return full}
        return String(full[range])
    }
    private var statusColor:Color {boss.status=="ready" ? teal : boss.status=="cooldown" ? .orange : .gray}
    var body:some View {
        VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){
                Toggle("攻略 \(boss.name) · \(model.fieldName(boss))",isOn:Binding(get:{model.bossIsChecked(boss)},set:{model.setBossChecked(boss,$0)})).labelsHidden().toggleStyle(.checkbox).controlSize(.small)
                Text(boss.name).font(.system(size:12,weight:.semibold)).lineLimit(1).help(boss.name)
                Spacer(minLength:0)
                Circle().fill(statusColor).frame(width:5,height:5).help(boss.statusLabel).accessibilityLabel(boss.statusLabel)
                if boss.status=="cooldown" {Text(boss.countdown).font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(.orange).fixedSize()}
                if active {Image(systemName:"scope").font(.system(size:10)).foregroundStyle(teal).help("当前攻略目标")}
            }
            HStack(spacing:5){
                Text(mapLabel).font(.system(size:10,weight:.medium)).foregroundStyle(teal).help(model.fieldName(boss))
                Text(model.dropInfo(boss)?.levelText ?? "—").foregroundStyle(.secondary).fixedSize()
                Text(model.dropInfo(boss)?.partText ?? "—").foregroundStyle(.secondary).lineLimit(1).help(model.dropInfo(boss)?.partText ?? "暂无掉落预览")
                Spacer(minLength:0)
                if boss.isAreaBoss {Label(boss.keyCount.map{String($0)} ?? "—",systemImage:"key.fill").foregroundStyle(.orange).help("区域BOSS · 剩余钥匙")}
            }.font(.system(size:10))
        }.padding(.horizontal,9).frame(height:58).frame(maxWidth:.infinity,alignment:.leading)

            .background(active ? teal.opacity(0.10) : Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(active ? teal.opacity(0.8) : Color.white.opacity(0.08),lineWidth:active ? 1.5 : 1))
            .opacity(model.bossIsChecked(boss) ? 1 : 0.5)
            .accessibilityElement(children:.contain)
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{!AppModel.shared.running}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if UpdateController.shared.readyToQuit{return .terminateNow}
        guard AppModel.shared.running else{return .terminateNow}
        Task{@MainActor in await AppModel.shared.prepareForExit();sender.reply(toApplicationShouldTerminate:true)}
        return .terminateLater
    }
}
@main struct BossAssistantApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body:some Scene{WindowGroup("首领助手"){MainView(model:.shared)}.defaultSize(width:1120,height:790).windowResizability(.contentMinSize).commands{CommandGroup(replacing:.newItem){};CommandMenu("游戏"){Button("重新检测"){Task{await AppModel.shared.detect()}}.keyboardShortcut("r");Button("停止攻击"){Task{await AppModel.shared.stopAttack()}}.keyboardShortcut(".");Divider();Button("注入脚本"){Task{await AppModel.shared.inject()}}}}}
}

struct BossFilterControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){
                Text("所需部位").font(.caption).foregroundStyle(.secondary)
                Button("不限"){model.clearPartFilter()}.tint(model.hasPartFilter ? Color.gray : Color.accentColor)
                ForEach(model.equipmentParts){part in
                    Toggle(part.name,isOn:Binding(get:{model.wantsPart(part.id)},set:{model.setWantedPart(part.id,$0)})).toggleStyle(.button)
                }
            }.controlSize(.small)
            HStack(spacing:12){
                Text("已勾选 \(model.checkedRowCount)/\(model.rows.count) · 共 \(model.unfilteredRows.count) 个首领").font(.caption).foregroundStyle(.secondary)
                Button("全选当前列表"){model.setVisibleBossesChecked(true)}
                Button("取消全选"){model.setVisibleBossesChecked(false)}
                Spacer()
                Text("每页最多20个").font(.system(size:10)).foregroundStyle(.tertiary)
            }.controlSize(.small)
        }.disabled(model.displayedArea==nil)
    }
}
