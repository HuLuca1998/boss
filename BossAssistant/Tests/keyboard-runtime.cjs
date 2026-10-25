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
