const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const handlers={},nativeKeys=new Set();let socket,chat=false,blur,followClears=0;
class Input {}
class FakeSocket{constructor(){socket=this;this.readyState=1;}send(data){this.last=JSON.parse(data);}}
const context={Laya:{Input,stage:{focus:null,on(name,owner,fn){handlers[name]=fn;}},Event:{KEY_DOWN:'down',KEY_UP:'up',BLUR:'blur'},InputManager:{hasKeyDown(code){return nativeKeys.has(code);}}},UIMgr:{inst:{IsOpen(){return chat;}}},EventFollowMgr:{inst:{ClearEventFollow(){followClears++;}}},WebSocket:FakeSocket,window:{addEventListener(name,fn){if(name==='blur')blur=fn;}},Date,setTimeout(fn,ms){if(ms===1000)fn();}};
const readyStage=context.Laya.stage;context.Laya.stage=undefined;
vm.runInNewContext(fs.readFileSync('BossAssistant/Resources/Runtime.js','utf8'),context);
const has=code=>context.Laya.InputManager.hasKeyDown(code);
const command=enabled=>{socket.onmessage({data:JSON.stringify({id:1,op:'keyboardMode',enabled})});assert.equal(socket.last.result.enabled,enabled);};
const key=(code,down)=>handlers[down?'down':'up']({keyCode:code,nativeEvent:{preventDefault(){}}});
assert.equal(has(87),false);context.Laya.stage=readyStage;command(true);
for(const [arrow,wasd] of [[38,87],[40,83],[37,65],[39,68]]){key(arrow,true);assert.equal(has(wasd),true);key(arrow,false);assert.equal(has(wasd),false);}
key(38,true);key(39,true);assert.equal(has(87)&&has(68),true);blur();assert.equal(has(87)||has(68),false);
chat=true;key(38,true);assert.equal(has(87),false);chat=false;
context.Laya.stage.focus=new Input();key(39,true);assert.equal(has(68),false);context.Laya.stage.focus=null;
key(38,true);command(false);assert.equal(has(87),false);
nativeKeys.add(87);assert.equal(has(87),true);nativeKeys.clear();
command(true);
socket.onmessage({data:JSON.stringify({id:2,op:'keyboardKeys',keys:[38,39,999]})});assert.equal(has(87)&&has(68),true);assert.equal(socket.last.result.pressed.length,2);
context.Date={now:()=>Date.now()+1500};assert.equal(has(87)||has(68),false);context.Date=Date;
socket.onmessage({data:JSON.stringify({id:3,op:'keyboardKeys',keys:[]})});assert.equal(has(87)||has(68),false);
key(38,true);socket.onclose();assert.equal(has(87),false);
const beforeRestore=followClears;
socket.onmessage({data:JSON.stringify({id:4,op:'keyboardMode',enabled:true,preserveNavigation:true})});assert.equal(socket.last.result.enabled,true);assert.equal(followClears,beforeRestore,'Automatic keyboard restore must not cancel hunting');
console.log('PASS: automatic restore preserves follow; directions, diagonal keys, release, blur, text entry, disable, original WASD, disconnect');
// ESC uses original return handlers, once per press; never confirms an unknown top dialog.
let returned=0;
class BaseMultiActivityView {}
class CommonTab2SubView { OncloseBtnClick(){this.baseView.Close();} }
context.BaseMultiActivityView=BaseMultiActivityView;context.CommonTab2SubView=CommonTab2SubView;
const shop=new BaseMultiActivityView();Object.assign(shop,{viewVo:{id:1043},gameObject:{visible:true},Layer:()=> 'MiddleLayer',Close(){returned++;}});
shop._commonTabSubView=new CommonTab2SubView();shop._commonTabSubView.baseView=shop;
const open=new Map([[1043,shop]]);Object.assign(context.UIMgr.inst,{_openViews:open,GetView:id=>open.get(id),GetOpenViewOrder:v=>v===shop?100:200});
const sendKeys=keys=>socket.onmessage({data:JSON.stringify({id:5,op:'keyboardKeys',keys})});
sendKeys([27]);assert.equal(returned,1);sendKeys([27]);assert.equal(returned,1,'hold does not close another page');sendKeys([]);
chat=true;sendKeys([27]);assert.equal(returned,1);chat=false;sendKeys([27]);assert.equal(returned,1,'typing press cannot later become a return');sendKeys([]);
const modal={viewVo:{id:1137},gameObject:{visible:true},Layer:()=> 'HighLayer'};open.set(1137,modal);sendKeys([27]);assert.equal(returned,1,'unknown top dialog blocks underlying shop return');sendKeys([]);open.delete(1137);
shop._commonTabSubView._closeCb=()=>{throw Error('custom callback must not run');};sendKeys([27]);assert.equal(returned,1);sendKeys([]);delete shop._commonTabSubView._closeCb;
sendKeys([27,38]);assert.equal(returned,2);assert.equal(has(87),true);sendKeys([]);
console.log('PASS: ESC original shop return, once per press, typing/unknown-modal/custom-callback guards, movement coexistence');
// BagView and StoreView inherit BaseView directly, not BaseMultiActivityView.
const bag={viewVo:{id:1010},gameObject:{visible:true},Layer:()=> 'MiddleLayer',Close(){returned++;}};
bag.tabSubView=new CommonTab2SubView();bag.tabSubView.baseView=bag;
open.clear();open.set(1010,bag);sendKeys([27]);assert.equal(returned,3,'direct BaseView bag uses original common tab return');sendKeys([]);
bag.tabSubView.OncloseBtnClick=()=>{throw Error('custom handler');};sendKeys([27]);assert.equal(returned,3);sendKeys([]);
console.log('PASS: direct BaseView backpack return; overridden handler rejected');
bag.tabSubView.OncloseBtnClick=CommonTab2SubView.prototype.OncloseBtnClick;
open.set(1005,{viewVo:{id:1005,name:'NotifyMsgView'},gameObject:{visible:true},Layer:()=> 'HighLayer'});
sendKeys([27]);assert.equal(returned,4,'passive game message layer must not block backpack return');sendKeys([]);
console.log('PASS: passive message layer ignored without ignoring unknown modal');

// Native resolved directions must override raw keys, including expiry and typing.
command(true);sendKeys([39]);nativeKeys.add(65);nativeKeys.add(68);
assert.equal(has(65),false);assert.equal(has(68),true);
key(37,true);assert.equal(has(65),false,'engine arrow events cannot corrupt native winner');
chat=true;assert.equal(has(68),false);chat=false;assert.equal(has(68),false,'typing clears held direction');
sendKeys([39]);context.Date={now:()=>Date.now()+1500};assert.equal(has(65)||has(68),false,'expiry cannot revive raw WASD');context.Date=Date;
sendKeys([]);assert.equal(has(65)||has(68),false,'release cannot revive raw WASD');
command(false);assert.equal(has(65),true,'disabled mode restores original engine');nativeKeys.clear();
console.log('PASS: native direction authority, raw opposite keys, typing and expiry');

// Combat hotkeys use visible native controls and consume each press even if blocked.
let ready=true,teleport=false,following=false,casts=[],toggles=0,selected=null,reject=false;
context.SceneMgr={inst:{GetCurSceneType:()=>1}};context.Scene={SceneType:{Wild:1,WildSync:5}};
const battleData={world:{},CheckCurHeroCreated:()=>true,CheckHasWorldInfo:()=>true,CheckCurHeroIsDead:()=>false,SetCurSelectingSkillId:id=>{selected=id;},GetCurSelectingSkillId:()=>selected,SetSkillSelectIsCancel(){}};
const battle={_fighting:true,battleData};
context.CombatMgr={inst:{GetBattleBySceneType:()=>ready?battle:null,GetCurRenderSceneType:()=>1}};
context.CombatTPMgr={inst:{GetIsTPing:()=>teleport}};
context.WildIdleModel={inst:{GetCurFieldId:()=>0}};
context.WildModel={inst:{CheckIsWildSync:()=>following,IsWildSyncLeader:()=>false}};
class MainMoreMenuSubView {OnlzidongBtnClick(){toggles++;}}
class MainSkillSubView {}
class SkillCardItem {
 GetSlotId(){return this.skillId-90;}
 IsDisableOperate(){return false;}
 GetBindBattle(){return battle;}
 OnClickHandler(){if(!reject)selected=this.skillId;}
 TryOperate(kind){if(kind==='skill'&&selected===this.skillId)casts.push(this.GetSlotId());}
}
Object.assign(context,{MainMoreMenuSubView,MainSkillSubView,SkillCardItem});
const root={visible:true},menu=Object.assign(new MainMoreMenuSubView(),{gameObject:{visible:true,parent:root},lzidongBtn:{visible:true,parent:root}});
const items={};for(let i=0;i<3;i++)items[i]=Object.assign(new SkillCardItem(),{skillId:101+i,gameObject:{visible:true,mouseEnabled:true,parent:root}});
const skills=Object.assign(new MainSkillSubView(),{gameObject:{visible:true,parent:root},activeSkillList:[11,12,13].map(slotId=>({slotId,skillId:slotId+90})),skillListScrollView:{GetShowItemDic:()=>items}});
open.clear();open.set(1002,{gameObject:root,Layer:()=> 'BottomLayer',_subViewList:[menu,skills]});
command(true);sendKeys([49,50,51,81]);assert.deepEqual(casts,[11,12,13]);assert.equal(toggles,1);
sendKeys([49,50,51,81]);assert.equal(casts.length,3);assert.equal(toggles,1,'heartbeat never toggles twice');
sendKeys([]);sendKeys([81]);assert.equal(toggles,2);
for(const block of ['typing','modal','loading','teleport','following','hidden','disabled','locked']){
 sendKeys([]);
 if(block==='typing')chat=true;
 if(block==='modal')open.set(999,modal);
 if(block==='loading')ready=false;
 if(block==='teleport')teleport=true;
 if(block==='following')following=true;
 if(block==='hidden')root.visible=false;
 if(block==='disabled')items[0].gameObject.mouseEnabled=false;
 if(block==='locked')skills.activeSkillList[0].lock=true;
 sendKeys([49]);assert.equal(casts.length,3,block);
 chat=false;open.delete(999);ready=true;teleport=false;following=false;root.visible=true;items[0].gameObject.mouseEnabled=true;skills.activeSkillList[0].lock=false;
 sendKeys([49]);assert.equal(casts.length,3,'blocked press cannot fire after '+block+' clears');
}
sendKeys([]);reject=true;selected=101;sendKeys([49]);assert.equal(casts.length,3,'native rejection cannot release stale selected skill');reject=false;
sendKeys([]);sendKeys([49,38]);assert.equal(casts.length,4);assert.equal(has(87),true);
sendKeys([]);chat=true;sendKeys([81]);chat=false;sendKeys([81]);assert.equal(toggles,2);
sendKeys([]);menu.lzidongBtn.visible=false;sendKeys([81]);assert.equal(toggles,2);
command(false);sendKeys([49]);assert.equal(casts.length,4);
console.log('PASS: three skill slots, native rejection, Q edge, heartbeat, typing/modal/scene/visibility/lock guards and movement coexistence');

// Run the shipped click/release handlers for all supported cache profiles.
for(const file of ['OriginalCache.bin','OriginalCache-f648a.bin','OriginalCache-dda2f.bin']){
 const raw=fs.readFileSync('BossAssistant/Resources/'+file).subarray(12,-20),key=Buffer.from('8fbf3b778fc986d812a84c9ebd4aba2d','hex');
 const source=Buffer.from(raw.map((v,i)=>v^key[i%16])).toString('utf8');
 const start=source.indexOf('SkillCardItem=class'),end=source.indexOf('RockerControl=class',start),card=source.slice(start,end);
 const click=card.slice(card.indexOf('OnClickHandler(){'),card.indexOf('Recycle(){'));
 const operate=card.slice(card.indexOf('TryOperate(e){'),card.indexOf('Destroy(){',card.indexOf('TryOperate(e){')));
 assert(click.startsWith('OnClickHandler(){')&&operate.startsWith('TryOperate(e){'),file);
 let selection=null,castCount=0,canUse=true,cost=true,banned=false,dead=false;
 const data={CheckHasWorldInfo:()=>true,CheckCurHeroIsDead:()=>dead,CheckCurHeroCanUseSkill:()=>canUse,GetCurHeroGlobalCD:()=>0,GetCurHeroTargetSkillGroupCD:()=>0,GetCurControlHeroEId:()=>1,GetTargetEntity:()=>({}),SetCurSelectingSkillId:id=>selection=id,GetCurSelectingSkillId:()=>selection,SetTryCastSkill:()=>castCount++};
 const ctx={SkillUtils:{IsSkillSlotBan:()=>banned,IsSkillCostFulfill:()=>cost},NotifyMgr:{inst:{ShowMsg(){},ShowSysMsg(){}}},SkillModel:{inst:{ShowForbidSpellSkillNotice(){}}},L:s=>s};
 const Native=vm.runInNewContext('(class { '+click+operate+' })',ctx),item=new Native();
 Object.assign(item,{GetBindBattle:()=>({battleData:data}),IsDisableOperate:()=>false,slotInfo:{slotCfg:{type:1},lock:false},skillInfo:{skillId:101,cd:0,IsIgnoreGlobalCD:()=>false},skillId:101,clickBtn:{}});
 function press(){selection=null;item.OnClickHandler();if(selection===item.skillId)item.TryOperate('skill');}
 press();assert.equal(castCount,1,file+' native success');
 for(const failure of ['cd','energy','ban','dead','cannotUse']){
  item.skillInfo.cd=failure==='cd'?1000:0;cost=failure!=='energy';banned=failure==='ban';dead=failure==='dead';canUse=failure!=='cannotUse';
  press();assert.equal(castCount,1,file+' native '+failure+' rejection');
 }
}
console.log('PASS: real shipped skill click/release methods across all three profiles, cooldown/energy/ban/death/cannot-cast rejection');
