const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
let now=1000000,socket,dialog,confirmations=0,queries=0,grants=0,clears=0;
const events={},cache=new Map(),messages=new Map([[1000,new Map([[0,[]]])],[1004,new Map([[7,[]]])],[1005,new Map([[0,[]]])]]);
function Retry(){confirmations++;dialog=null;}
const failure={},pipeline={defaultFailStep:failure,curSteps:new Set([failure])};
const model={_chatDataMap:messages,SplitRedPacketMessage(m){const [id,msg,expiry,type]=m.split('|');return {id,message:msg,expiredTimeStamp:Number(expiry),hongbaoMainId:Number(type)}},GetRedPacketInfoById(id){return cache.get(id)},GetHongbaoMainCfg(type){return type===1?{hongbao_channel:[1000]}:type===5?{hongbao_channel:[1004]}:null},CheckRedPacketCanGrab(type){return type!==5},RequestRedPacketInfo(id){queries++},GrabRedPacket(id){grants++}};
const context={Date:class extends Date {static now(){return now}},Math,console,WebSocket:class{constructor(){socket=this;this.readyState=1}send(s){this.last=JSON.parse(s)}},setTimeout(fn,ms){if(ms===1000)fn()},window:{},L:k=>({login_txt_13:'帐号校验失败，是否重新校验？',login_txt_14:'服务器连接失败，是否重新连接？',login_txt_21:'登录服连接失败，是否尝试重新连接'})[k]||k,Laya:{},LoginModel:{inst:{loginPipeline:pipeline}},LoginEvent:{OnLoginS2C:'login'},ChatDefine:{ChatEvent:{ReceiveOneMsg:'chat'}},EventMgr:{AddEvent(e,o,fn){events[e]=fn}},UIMgr:{inst:{GetView(id){return dialog?.id===id?dialog:null}}},SDKMgr:{inst:{CheckIsH5ByConfig(){return false}}},ChatModel:{inst:model},Time:{GetServerTime(){return now/1000}},PlayerModel:{inst:{role:{id:1}}},IsNullOrUndefined:x=>x==null,ConfigMgr:{inst:{GetKey(){return {huobi_id:3}}}},configTable:{hongbao_main:'hb'},EventFollowMgr:{inst:{ClearTargetSceneEventFollow(){clears++}}},Scene:{SceneType:{Wild:1}},SceneMgr:{inst:{GetCurSceneType(){return 1}}},CombatMgr:{inst:{GetBattleBySceneType(){return null}}}};
vm.createContext(context);vm.runInContext(fs.readFileSync('BossAssistant/Tests/Fixtures/RedPacketVo.js','utf8'),context);vm.runInContext(fs.readFileSync('BossAssistant/Resources/Runtime.js','utf8'),context);
let id=0;function rpc(op,fields={}){socket.onmessage({data:JSON.stringify({id:++id,op,...fields})});assert(!socket.last.error,socket.last.error);return socket.last.result}
function open(text,fn=Retry.bind(null)){dialog={id:1183,gameObject:{visible:true,destroyed:false},args:{content:text,confirmFun:fn,cancelFun:null},left1Btn:{visible:true},Onleft1BtnClick(){this.args.confirmFun()},OnrightBtnClick(){this.args.confirmFun()}}}
let status=rpc('assistStatus');assert.equal(status.version,1,'Works before a wild snapshot/role is ready');
open('服务器连接失败，是否重新连接？');status=rpc('assistStatus');assert(status.dialog.canConfirm);const token=status.dialog.token;
rpc('assistRun',{confirmToken:'stale',locked:false});assert.equal(confirmations,0);
rpc('assistRun',{confirmToken:token,locked:false});assert.equal(confirmations,1);rpc('assistRun',{confirmToken:token,locked:false});assert.equal(confirmations,1);
now+=11000;open('服务器连接失败，是否重新连接？',function ShowServerListView(){});status=rpc('assistStatus');assert.equal(status.dialog.canConfirm,false,'Identical fallback text with a different action must not be clicked');
open('购买礼包？');status=rpc('assistStatus');assert.equal(status.dialog.kind,'unknown');rpc('assistRun',{confirmToken:status.dialog.token});assert.equal(confirmations,1);
events.login({result:200104});open('您的账号已在别处登录');status=rpc('assistStatus');assert.equal(status.dialog.token,status.replacedEvents[0].token,'Error observation and dialog are one occurrence');assert.equal(rpc('assistStatus').replacedEvents.length,1);
rpc('assistRun',{locked:true,confirmToken:status.dialog.token});assert.equal(confirmations,1);assert.equal(socket.last.result.locked,true);socket.onmessage({data:JSON.stringify({id:++id,op:'attackMode'})});assert.equal(socket.last.error,'account_recovery_locked');
rpc('assistRun',{locked:false,confirmToken:status.dialog.token});assert.equal(confirmations,2);
function msg(channel,id,type=1){return {channel_id:channel,session_id:channel===1004?7:0,type:8,message:`${id}|红包|${now/1000+3600}|${type}`}}
const huge='90071992547409931234';events.chat({data:msg(1000,huge)});events.chat({data:msg(1000,huge)});events.chat({data:msg(1005,'private')});assert.equal(rpc('assistStatus').queued,1);
rpc('assistRun',{redPackets:true});assert.equal(queries,1);assert.equal(grants,0);
cache.set(huge,{id:huge,channel_id:1000,session_id:0,money_type:1,cur_num:2,agents:[]});now+=4000;rpc('assistRun',{redPackets:true});assert.equal(grants,1);now+=12000;rpc('assistRun',{redPackets:true});assert.equal(grants,1,'Uncertain grant is queried, never blindly retried');assert.equal(rpc('assistStatus').claimed,0);
cache.get(huge).agents=[{agent_id:1,money:3}];now+=4000;status=rpc('assistRun',{redPackets:true});assert.equal(status.claimed,1,'Only server state confirms a successful claim');now+=4000;assert.equal(rpc('assistRun',{redPackets:true}).claimed,1);
events.chat({data:msg(1004,'assist',5)});cache.set('assist',{id:'assist',channel_id:1004,session_id:7,money_type:5,cur_num:1,agents:[]});now+=4000;rpc('assistRun',{redPackets:true});assert.equal(grants,1,'Assist currency cap respected');
events.chat({data:msg(1000,'mismatch')});cache.set('mismatch',{id:'mismatch',channel_id:1004,session_id:0,money_type:1,cur_num:1,agents:[]});now+=4000;rpc('assistRun',{redPackets:true});assert.equal(grants,1,'Server channel mismatch rejected');
console.log('PASS: role-independent dialogs, safe callback classification, stale/duplicate confirmation, account lock, error/dialog deduplication, channel filters, lossless IDs, grant acknowledgement, no blind duplicate grants, currency cap and context guards');
// Passive popup lifecycle and durable acknowledgement contract.
context.GameCoreEvent={OpenView:'open',CloseView:'close'};
const views=new Map();context.UIMgr.inst._openViews=views;
context.UIMgr.inst.GetView=id=>views.get(Number(id))||(dialog?.id===Number(id)?dialog:null);
let batch=rpc('assistStatus').popupEvents;
while(batch.length){batch=rpc('assistRun',{popupAck:Number(batch.at(-1).eventId.split(':').at(-1))}).popupEvents;}
let reads=0,actions=0;const args={title:'诊断弹窗',content:'只读测试',token:'secret',confirmFun(){actions++}};
Object.defineProperty(args,'dangerous',{enumerable:true,get(){reads++;throw Error('getter executed')}});args.self=args;
const view={viewVo:{name:'ExamplePopView',type:1},gameObject:{visible:true},args,confirmBtn:{label:'确认',visible:true}};
views.set(9000,view);events.open(9000);
status=rpc('assistStatus');assert.equal(status.popupEvents.length,1);const first=status.popupEvents[0];
assert.equal(first.phase,'opened');assert.equal(first.data.parameters.args.token,'[REDACTED]');assert.equal(first.data.parameters.args.dangerous,'[ACCESSOR_NOT_READ]');assert.equal(reads,0);assert.equal(actions,0);
assert.equal(rpc('assistStatus').popupEvents.length,1,'Unchanged popup is not duplicated');
args.content='更新文案';status=rpc('assistStatus');assert.equal(status.popupEvents[1].phase,'updated');
views.delete(9000);events.close(9000);status=rpc('assistStatus');assert.equal(status.popupEvents[2].phase,'closed');
const ack=Number(status.popupEvents.at(-1).eventId.split(':').at(-1));assert.equal(rpc('assistRun',{popupAck:ack}).popupEvents.length,0);
views.set(9000,view);events.open(9000);status=rpc('assistStatus');assert.notEqual(status.popupEvents[0].occurrenceId,first.occurrenceId,'Reused component creates new occurrence');assert.equal(actions,0);
console.log('PASS: popup lifecycle, deduplication, reopen, ACK, secret redaction, accessor/callback isolation');
// Known popup actions: opt-in, dwell, identity, single attempt, account protection.
views.clear();dialog=null;let idleClaims=0,rewardCloses=0;
context.WildIdleModel={inst:{incomeInfo:[{id:1}],GetCurAreaId(){return 7},GetCurFieldId(){return 22}}};
const idle={viewVo:{name:'WildIdleRewardView',type:1},gameObject:{visible:true},rewardReceiveBtn:{visible:true},OnrewardReceiveBtnClick(){idleClaims++}};
views.set(1023,idle);rpc('assistStatus');rpc('assistRun',{idleReward:true});assert.equal(idleClaims,0,'Dwell prevents instant processing');now+=3000;
rpc('assistRun',{});assert.equal(idleClaims,0,'Disabled rule has no action');
rpc('assistRun',{idleReward:true,locked:true});assert.equal(idleClaims,0,'Account lock blocks popup automation');
idle.rewardReceiveBtn.disabled=true;rpc('assistRun',{idleReward:true,locked:false});assert.equal(idleClaims,0);
idle.rewardReceiveBtn.disabled=false;rpc('assistRun',{idleReward:true});assert.equal(idleClaims,1);
now+=12000;rpc('assistRun',{idleReward:true});assert.equal(idleClaims,1,'Uncertain acknowledgement never repeatedly claims');
views.delete(1023);events.close(1023);
context.BaseView=function(){};context.BaseView.prototype.OnMaskBgClick=function(){this.Close(false)};
const notice={viewVo:{id:1017,name:'NotifyItemGainView',type:1,mask:2},gameObject:{visible:true},gainItems:[{id:1}],Close(){rewardCloses++;this.gameObject.visible=false},OnshareMomentBtnClick(){throw Error('must not share')}};
notice.OnMaskBgClick=context.BaseView.prototype.OnMaskBgClick;context.UIAdaptMgr={inst:{maskView:notice,closeTipsGo:{visible:true},_OnMaskClick(){this.maskView.OnMaskBgClick()}}};
views.set(1017,notice);events.open(1017);now+=3000;rpc('assistRun',{blankClose:true});assert.equal(rewardCloses,1);now+=3000;rpc('assistRun',{blankClose:true});assert.equal(rewardCloses,1);
notice.gameObject.visible=true;notice.viewVo.mask=1;events.open(1017);now+=3000;rpc('assistRun',{blankClose:true});assert.equal(rewardCloses,1,'Non-blank mask rejected');
console.log('PASS: known reward actions, opt-in/dwell/disabled/lock gates, exact component guard, no repeated claim or share');

notice.viewVo.mask=2;notice.OnMaskBgClick=function(){throw Error('custom purchase/box action must not run')};events.open(1017);now+=3000;rpc('assistRun',{blankClose:true});assert.equal(rewardCloses,1,'Overridden mask handler rejected');
notice.OnMaskBgClick=context.BaseView.prototype.OnMaskBgClick;context.UIAdaptMgr.inst.closeTipsGo.visible=false;events.open(1017);now+=3000;rpc('assistRun',{blankClose:true});assert.equal(rewardCloses,1,'Invisible close hint rejected');
context.UIAdaptMgr.inst.closeTipsGo.visible=true;rpc('assistRun',{blankClose:false});assert.equal(rewardCloses,1,'Unified toggle disabled');rpc('assistRun',{blankClose:true,locked:true});assert.equal(rewardCloses,1,'Account lock blocks generic dismissal');
console.log('PASS: unified blank-close topmost target, mask2/hint, standard handler identity, override rejection, settings and lock gates');
// Reward notices use an INTERNAL CommonBg1SubView, with no outer mask flag.
views.clear();context.UIAdaptMgr.inst.maskView=null;context.CommonBg1SubView=function(){};
context.CommonBg1SubView.prototype.OncloseBtnClick=function(){this.baseView.Close()};
let internalClosed=0;
const internal={viewVo:{id:1017,name:'NotifyItemGainView',type:1},gameObject:{visible:true},Close(){internalClosed++;this.gameObject.visible=false},OnshareMomentBtnClick(){throw Error('never share')}};
internal.commonBg1SubView={baseView:internal,closeBtn:{visible:true},guanbiTxt:{text:'点击空白处关闭'},OncloseBtnClick:context.CommonBg1SubView.prototype.OncloseBtnClick};
views.set(1017,internal);events.open(1017);now+=4000;
rpc('assistRun',{blankClose:false,locked:false});assert.equal(internalClosed,0);
const internalStatus=rpc('assistRun',{blankClose:true});assert.equal(internalClosed,1,'Internal blank close works without cfg.mask2');assert(internalStatus.popupEvents || []);
now+=4000;rpc('assistRun',{blankClose:true});assert.equal(internalClosed,1,'Closed view is not clicked again');
internal.gameObject.visible=true;internal.commonBg1SubView.OncloseBtnClick=function(){throw Error('custom handler must not run')};events.open(1017);now+=4000;rpc('assistRun',{blankClose:true});assert.equal(internalClosed,1,'Custom internal handler rejected');
console.log('PASS: internal background blank-close, no outer mask, unified toggle, normal handler identity, no sharing');
// New chat packets bypass native polling and pre-query; server data still confirms outcome.
views.clear();dialog=null;rpc('assistRun',{redPackets:true,fastRedPackets:true,locked:false});now+=1000;
let beforeFast=grants,beforeQueries=queries;events.chat({data:msg(1000,'fast-live')});
assert.equal(grants,beforeFast+1,'Live packet claims inside message callback');assert.equal(queries,beforeQueries,'No pre-query wait');
events.chat({data:msg(1000,'fast-live')});assert.equal(grants,beforeFast+1,'Repeated broadcast cannot regrant');
let fast=rpc('assistStatus').packets.find(p=>p.id==='fast-live');assert.equal(fast.requestDelayMs,0);assert.equal(fast.attempted,true);assert.notEqual(fast.serverStatus,1,'Request is not success');
events.chat({data:msg(1000,'fast-burst')});assert.equal(grants,beforeFast+1,'Burst gets short spacing');now+=200;rpc('assistRun',{redPackets:true,fastRedPackets:true});assert.equal(grants,beforeFast+2);
cache.set('fast-live',{id:'fast-live',channel_id:1000,session_id:0,money_type:1,cur_num:1,agents:[{agent_id:1,money:7}]});now+=500;let confirmed=rpc('assistRun',{redPackets:true,fastRedPackets:true}).packets.find(p=>p.id==='fast-live');assert.equal(confirmed.serverStatus,1);assert.equal(confirmed.myAmount,7);
rpc('assistRun',{redPackets:false,fastRedPackets:true});beforeFast=grants;events.chat({data:msg(1000,'disabled-live')});assert.equal(grants,beforeFast,'Off switch disables immediate claims');
rpc('assistRun',{redPackets:true,fastRedPackets:true,locked:true});events.chat({data:msg(1000,'locked-live')});assert.equal(grants,beforeFast,'Account lock disables immediate claims');
console.log('PASS: immediate live packet claim, no pre-query, zero callback delay, 200ms burst spacing, server verification, dedupe/off/lock');

// Reproduce the original game's follow rejection while no hunt is running.
let followToasts=0,autoChanges=0;
context.WildModel={inst:{CheckIsWildSync:()=>true,IsWildSyncLeader:()=>false,ChangeAutoSkill(){followToasts++;}}};
context.CombatMgr.inst.GetBattleBySceneType=()=>({_fighting:true,battleData:{world:{battleInitData:{}},CheckCurHeroCreated:()=>true}});
context.CombatMgr.inst.GetCurRenderSceneType=()=>1;
context.WildIdleModel.inst.GetFieldCfg=()=>({field_name:'field'});
for(let i=0;i<100;i++)rpc('assistRun',{locked:true});
assert.equal(followToasts,0,'Account protection with hunt off must never repeatedly change followed auto combat');
socket.onmessage({data:JSON.stringify({id:++id,op:'attackMode',areaId:7})});
assert.equal(socket.last.error,'account_recovery_locked');
rpc('assistRun',{locked:false});
socket.onmessage({data:JSON.stringify({id:++id,op:'attackMode',areaId:7})});
assert.equal(socket.last.error,'team_following','Following blocks hunt before any combat mutation');
assert.equal(followToasts,0);
console.log('PASS: 100 locked idle polls and following attack guard produce no follow rejection notifications');
