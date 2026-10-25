const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
let socket,scene=1,render=1,area=7,ready=true,teleport=false,callback;
const auto=[],cleared=[],followed=[];
const data={world:{battleInitData:{dungeon_id:3600132}},GetHeroPos:()=>({x:12,y:0,z:34}),CheckCurHeroCreated:()=>ready};
class Vector3 {scale(){return this;}clone(){return new Vector3();}}
const context={
 WebSocket:class {constructor(){socket=this;this.readyState=1;}send(v){this.last=JSON.parse(v);}},
 setTimeout(fn,ms){if(ms===1000)fn();},Date,
 Scene:{SceneType:{Wild:1,WildSync:5}},SceneMgr:{inst:{GetCurSceneType:()=>scene}},
 CombatMgr:{inst:{GetBattleBySceneType:()=>({_fighting:true,battleData:data}),GetCurRenderSceneType:()=>render,GetHightestPriorityBattle:()=>({battleData:{IsHeroAutoUseSkill:()=>false}}),GetWildBattleData:()=>null,GetWildSyncBattleData:()=>null}},
 WildIdleModel:{inst:{GetCurAreaId:()=>area,GetCurFieldId:()=>21,GetFieldCfg:()=>({field_name:'红叶王庭Ⅰ'}),GetAreaNameByAreaId:()=> '红叶王庭',CheckAreaIsUnlock:()=>true,HandleWildTPInfo(tp,mode,fn){callback=fn;}}},
 CombatTPMgr:{inst:{GetIsTPing:()=>teleport}},
 ConfigMgr:{inst:{GetKey(table,id){return {inst_name:'试炼秘境14-2',name:'巢母'};},GetCfg:()=>({GetCfgList:()=>[{area:7,area_name_show:'红叶王庭'}]})}},
 configTable:{instance:1,field:2,monster_type:3},L:v=>v,
 WildModel:{inst:{insId2WildReviveInfoMap:new Map([[10021,{info:[{point_id:501,revive_time:0}]}]]),CheckIsWildSync:()=>false,ChangeAutoSkill:v=>auto.push(v)}},
 MapModel:{inst:{GetMonsterItemDataListByAreaId:()=>[{bossId:1,insId:10021,pointId:501,pointIndex:0,mapId:1,uid:123}],GetWildPointCD:()=>0,CheckIsCanTransfer:()=>true,RequestBossReviveInfo(){}}},
 EventFollowMgr:{inst:{GetEventFollowVo:()=>null,ClearTargetSceneEventFollow:type=>cleared.push(type),ClearEventFollow(){throw Error('Must not clear dungeon follow');},ShowEventFollowByParams:v=>followed.push(v)}},
 Time:{GetServerTime:()=>1234},Laya:{Vector3},WildMapMgr:{inst:{GetMapPointByTypeAndId1(){}}},MapTool:{GetCommonTpPos:()=>({})},MapBossIcon:{2:'boss'}
};
vm.runInNewContext(fs.readFileSync('BossAssistant/Resources/Runtime.js','utf8'),context);
let id=0;
function request(op,fields={}){socket.onmessage({data:JSON.stringify({id:++id,op,...fields})});return socket.last;}
function enterDungeon(){scene=render=2;}
function returnToWild(){scene=render=1;}
area=0;assert.equal(request('list').error,'game_not_ready','Loading must not query boss or restore control early');area=7;
assert.equal(request('list').result.location.kind,'wild');
assert.equal(request('list').result.location.heroPos.x,12);
assert.equal(request('attackMode',{areaId:7}).error,undefined);
assert.equal(auto.length,1);
assert.equal(request('goto',{areaId:7,bossId:1,insId:10021,pointId:501}).error,undefined);
const staleCallback=callback;
enterDungeon();
const dungeon=request('list').result;
assert.equal(dungeon.areaId,7,'Last wild area is still retained by the game');
assert.equal(dungeon.location.kind,'dungeon','Actual scene overrides stale wild area');
assert.equal(dungeon.location.name,'试炼秘境14-2');
assert.equal(dungeon.navigation,null);
assert.equal(auto.length,1,'Pausing must not toggle dungeon auto combat');
staleCallback();assert.equal(followed.length,0,'Old teleport callback must not restore following');
assert.equal(request('attackMode',{areaId:7}).error,'hunt_scene_unavailable');
assert.equal(request('goto',{areaId:7}).error,'hunt_scene_unavailable');
assert.equal(auto.length,1);
assert.equal(request('stop').result.stopped,true);assert.equal(auto.length,1,'Stopping a paused hunt must preserve dungeon combat');
returnToWild();ready=false;
assert.equal(request('attackMode',{areaId:7}).error,'hunt_scene_unavailable');
ready=true;teleport=true;
assert.equal(request('attackMode',{areaId:7}).error,'hunt_scene_unavailable');
teleport=false;
assert.equal(request('attackMode',{areaId:8}).error,'hunt_scene_unavailable');
assert.equal(request('attackMode',{areaId:7}).error,undefined);
assert.equal(request('goto',{areaId:7,bossId:1,insId:10021,pointId:501}).error,undefined);
callback();assert.equal(followed.length,1,'Returning to the correct ready area permits a fresh target');
assert.ok(cleared.every(type=>type===1),'Only clear wild following');
console.log('PASS: real scene over stale wild area, dungeon identity, pause, dungeon auto combat preserved, stale callback blocked, loading/teleport/wrong-area guards, resume');
// Regional bosses use authoritative area-boss state and require a real key.
scene=render=1;area=7;ready=true;teleport=false;
let keys=0,areaInfo={status:1,revive_time:0};
context.types={area_boss:{status:{alive:1}}};
context.AreaBossModel={inst:{boxKeyItemId:88,boxKeyDayLimit:3,GetTodayRewardTimes:()=>keys,GetAreaBossInfo:()=>areaInfo,GetAreaBossIsNotRewarded:()=>false}};
context.MapModel.inst.GetMonsterItemDataListByAreaId=(a,include)=>{assert.equal(include,true);return [{bossId:99,insId:10021,pointId:502,pointIndex:1,mapId:1,uid:'area',monsterType:3}]};
let regional=request('list').result;assert.equal(regional.rows[0].kind,'areaBoss');assert.equal(regional.rows[0].status,'ready');assert.equal(regional.rows[0].keyCount,0);assert.equal(regional.areaBossKey.count,0);
const target={areaId:7,bossId:99,insId:10021,pointId:502};assert.equal(request('goto',target).error,'area_boss_no_key');
keys=2;assert.equal(request('goto',target).result.requested,true);
areaInfo={status:2,revive_time:1300};regional=request('list').result;assert.equal(regional.rows[0].status,'cooldown');assert.equal(regional.rows[0].cdSeconds,66);assert.equal(request('goto',target).error,'target_not_confirmed_ready');
areaInfo=null;assert.equal(request('list').result.rows[0].status,'unknown');areaInfo={status:1,revive_time:0};
areaInfo={status:1};assert.equal(request('list').result.rows[0].status,'ready','Alive boss without timestamp is refreshed');
areaInfo={status:1,revive_time:999999};assert.equal(request('list').result.rows[0].status,'ready','Alive overrides stale future countdown');
areaInfo={status:2,revive_time:'1300'};assert.equal(request('list').result.rows[0].cdSeconds,66,'Numeric string timestamp accepted');
areaInfo={status:2,revive_time:1200};assert.equal(request('list').result.rows[0].status,'unknown','Expired dead state awaits real server revival');
areaInfo={status:2};assert.equal(request('list').result.rows[0].status,'unknown','Missing dead timestamp is not invented alive');
areaInfo={status:1};
// The owned target's result alone can consume a key; no substitute-item fallback.
let clock=100000,opened=0;context.Date=class extends Date{static now(){return clock}};
const view={viewVo:{id:1276,name:'AreaBossResultView',type:1},gameObject:{visible:true},data:{ins_id:10021,mon_point:502},open:false,normalBtn:{visible:true},OnnormalBtnClick(){opened++}};
context.UIMgr={inst:{GetView:id=>id===1276?view:null}};
request('assistStatus');clock+=3000;request('assistRun',{areaBossBox:true,huntArea:7});assert.equal(opened,0,'Old target timestamp mismatch cannot spend keys');
// Refresh owned intent under the same clock.
request('goto',target);clock+=3000;keys=0;request('assistRun',{areaBossBox:true,huntArea:7});assert.equal(opened,0,'No key cannot consume alternate item');keys=2;request('assistRun',{areaBossBox:true,huntArea:8});assert.equal(opened,0,'Different hunt area rejected');request('assistRun',{areaBossBox:true,huntArea:7});assert.equal(opened,1);
clock+=5000;request('assistRun',{areaBossBox:true,huntArea:7});assert.equal(opened,1,'One request until server confirms');
console.log('PASS: regional boss authoritative state, cooldown, zero-key gate, area key snapshot, owned box single request');
// A paused native bounty helper blocks the standard route entry; use normal manual path API.
let paused=true,pathCalls=[],pathClears=[];
context.types.bounty_task={helper_status:{action:1}};
context.BountyTaskModel={inst:{GetAutoBountyStatus:()=>1}};context.AutoBountyTaskMgr={inst:{get isClientAutoBountyPause(){return paused}}};
context.QVector3=class{constructor(x,y,z){Object.assign(this,{x,y,z})}};
context.MapPathMgr={inst:{DoubleAStar(){return [{x:0,y:0,z:0},{x:100,y:0,z:200}]}}};
let hero={x:0,y:0,z:0};data.GetHeroPos=()=>hero;data.SetClientHeroPathInfo=(path,noAI)=>pathCalls.push({path,noAI});data.ClearClientHeroPathInfo=all=>pathClears.push(all);
context.WildMapMgr.inst.GetMapPointByTypeAndId1=(map,type,point,v)=>Object.assign(v,{x:100,y:0,z:200});
request('goto',target);callback();assert.equal(pathCalls.length,1);assert.equal(pathCalls[0].noAI,true);assert.equal(pathCalls[0].path[1].x,10000,'Engine path coordinates are centimeters');
assert.equal(request('list').result.navigation.mode,'pausedBountyPath');assert.equal(request('list').result.navigation.phase,'moving');
hero={x:100,y:0,z:200};assert.equal(request('list').result.navigation.phase,'attacking');assert.equal(pathClears.at(-1),true);
paused=false;request('goto',target);callback();assert.equal(pathCalls.length,1,'Active bounty must not be fought or modified');assert.equal(request('list').result.navigation.phase,'blocked');
console.log('PASS: paused-bounty path fallback, engine units, arrival combat, own-path cleanup, active-bounty conflict');
// Zero keys must leave a regional combat zone, but never affect a normal zone or manual pause.
let inRegional=true,exitsBefore=auto.length;
context.AreaBossMgr={inst:{GetIsInAreaBossArea:()=>inRegional}};
context.MapModel.inst.GetMonsterItemDataListByAreaId=()=>[{bossId:1,insId:10021,pointId:501,pointIndex:0,mapId:1,uid:123,monsterType:2}];
keys=0;request('assistRun',{avoidNoKeyBoss:false,huntArea:7});assert.equal(auto.length,exitsBefore,'Manual/pause gate');
inRegional=false;request('assistRun',{avoidNoKeyBoss:true,huntArea:7});assert.equal(auto.length,exitsBefore,'Normal boss combat is untouched');
inRegional=true;keys=1;request('assistRun',{avoidNoKeyBoss:true,huntArea:7});assert.equal(auto.length,exitsBefore,'Positive keys permit regional combat');
keys=0;clock+=20000;request('assistRun',{avoidNoKeyBoss:true,huntArea:8});assert.equal(auto.length,exitsBefore,'Wrong area cannot move player');
request('assistRun',{avoidNoKeyBoss:true,huntArea:7});assert.equal(auto.at(-1),false);assert.equal(request('list').result.navigation.phase,'leavingNoKey');callback();assert.equal(request('assistStatus').result.noKeyBossExits,1);
console.log('PASS: zero-key regional exit, battle disabled, normal-zone/positive-key/manual/area guards');
