import Foundation
import SwiftUI
import AppKit

struct NearbyMonster:Codable,Identifiable {
    let eid:String;let name:String;let cfgId:Int;let hp:Double;let maxHp:Double;let distance:Double
    let selected:Bool;let requested:Bool
    var id:String {eid}
    var fraction:Double {max(0,min(1,hp/maxHp))}
    var healthText:String {"\(hp.formatted(.number.precision(.fractionLength(0)))) / \(maxHp.formatted(.number.precision(.fractionLength(0))))"}
}
struct NearbyTargetStatus:Codable {
    let version:Int;let enabled:Bool;let autoHighest:Bool;let scope:String;let sceneType:Int?;let ready:Bool;let locked:Bool;let radius:Double?;let rows:[NearbyMonster]
}

@MainActor final class NearbyTargetPanel:NSWindowController,NSWindowDelegate {
    static var shared:NearbyTargetPanel?
    private let model:AppModel
    init(model:AppModel){
        self.model=model
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:430,height:250),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        panel.title="附近怪物 · 集火选择";panel.level = .floating;panel.isReleasedWhenClosed=false
        panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.becomesKeyOnlyIfNeeded=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentViewController=NSHostingController(rootView:NearbyTargetView(model:model))
        super.init(window:panel);panel.delegate=self;panel.minSize=NSSize(width:380,height:220);panel.center()
    }
    private var lastCount = -1
    static func fit(count:Int){
        guard let shared,let window=shared.window,window.isVisible,count != shared.lastCount else{return}
        shared.lastCount=count
        let screen=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        let capacity=max(1,Int((screen.height-200)/29))
        let columns=max(1,Int(ceil(Double(count)/Double(capacity))))
        let width=min(screen.width-30,max(430,Double(columns)*350))
        let height=min(screen.height-60,max(220,Double(Int(ceil(Double(max(1,count))/Double(columns))))*29+135))
        var frame=window.frame
        frame.origin.y += frame.height-height;frame.size=NSSize(width:width,height:height)
        frame.origin.x=max(screen.minX,min(frame.origin.x,screen.maxX-width))
        frame.origin.y=max(screen.minY,min(frame.origin.y,screen.maxY-height))
        window.setFrame(frame,display:true,animate:false)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    static func present(model:AppModel){
        if shared==nil {shared=NearbyTargetPanel(model:model)}
        shared?.showWindow(nil);shared?.window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification:Notification){model.closeNearbyTargets()}
}

struct NearbyTargetView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack {
                Toggle("开启列表",isOn:Binding(get:{model.targetingEnabled},set:{value in Task{await model.setTargetEnabled(value)}})).disabled(model.targetBusy)
                Spacer()
                Toggle("自动集火最高血量",isOn:Binding(get:{model.targetAutoHighest},set:{value in Task{await model.setTargetAuto(value)}})).disabled(!model.targetingEnabled || !model.connected || model.targetBusy || (model.recoveryLocked && !model.targetAutoHighest)).help("默认关闭；按当前剩余血量选择。手动点选会退出自动模式。")
            }
            HStack {Text("血量从高到低 · 点击手动集火").font(.caption).foregroundStyle(.secondary);Spacer();Text("\(model.nearbyTargets?.rows.count ?? 0) 个").font(.caption).foregroundStyle(.secondary)}
            Text(model.targetMessage).font(.caption).foregroundStyle(model.recoveryLocked ? Color.orange : .secondary).lineLimit(1).help(model.targetMessage)
            Divider()
            GeometryReader {geometry in
                let rows=model.nearbyTargets?.rows ?? []
                let capacity=max(1,Int(geometry.size.height/29))
                let columns=max(1,Int(ceil(Double(rows.count)/Double(capacity))))
                if rows.isEmpty {
                    Text(model.targetingEnabled && model.connected && model.nearbyTargets?.ready == true ? "当前范围内没有存活怪物" : "开启后显示范围内的怪物").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:columns),spacing:5){
                        ForEach(rows){monster in
                            Button {Task{await model.selectNearbyMonster(monster)}} label:{
                                NearbyMonsterRow(monster:monster)
                            }.buttonStyle(.plain).disabled(!model.targetingEnabled || model.targetBusy || model.recoveryLocked)
                            .accessibilityLabel("集火 \(monster.name) 编号 \(monster.eid)，血量 \(String(format:"%.1f%%",monster.fraction*100))\(monster.selected ? "，已选中" : monster.requested ? "，等待生效" : "")")
                        }
                    }
                }
            }
        }.padding(12).frame(minWidth:350,minHeight:170).preferredColorScheme(.dark)
    }
}

private struct NearbyMonsterRow:View {
    let monster:NearbyMonster
    private var color:Color {monster.selected ? .green : .orange}
    var body:some View {
        HStack(spacing:5){
            Image(systemName:monster.selected ? "scope" : monster.requested ? "clock" : "circle").font(.caption2).foregroundStyle(monster.selected ? Color.green : Color.secondary).frame(width:13)
            Text(monster.name).font(.system(size:12,weight:monster.selected ? .semibold : .regular)).lineLimit(1)
            Text("#\(monster.eid)").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
            MonsterHealthBar(fraction:monster.fraction,color:color).frame(minWidth:70).frame(height:18)
        }.padding(.horizontal,6).frame(height:24).background(monster.selected ? Color.green.opacity(0.08) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:5)).contentShape(Rectangle())
    }
}
private struct MonsterHealthBar:View {
    let fraction:Double
    let color:Color
    var body:some View {
        GeometryReader {bar in
            ZStack(alignment:.leading){
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.opacity(0.65)).frame(width:bar.size.width*CGFloat(fraction))
                Text(String(format:"%.1f%%",fraction*100)).font(.system(size:10,weight:.medium,design:.monospaced)).frame(maxWidth:.infinity)
            }
        }
    }
}
