const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
let socket,clock=2000,scene=2,render=2,ready=true,teleport=false,locked=false;
const controller={curHeroSelectTargetEid:null},ai={playerSelectedTargetEid:null},calls=[];
const entries={};
const hero={eid:1,type:2,Get:k=>k==='rt'?{pos:{x:0,y:0,z:0}}:null,dead:false};entries[1]=hero;
function monster(eid,hp,x=3,options={}){
 const m={eid,type:options.type??3,cfgId:700,dead:false,enemy:true,hp,maxHp:200,...options};
 m.Get=k=>k==='rt'?{pos:{x,y:0,z:0}}:k==='attr'?{GetNowHp:()=>m.hp,GetMaxHp:()=>m.maxHp}:null;entries[eid]=m;return m;
}
const a=monster(10,100),b=monster(11,150),dead=monster(12,999,2,{dead:true}),far=monster(13,999,20),friend=monster(14,999,3,{enemy:false});
monster(15,999,3,{type:2});monster(16,NaN);
function makeWorld(){return {localAgentId:99,dataCenter:{entities:entries},GetEntity:id=>entries[id],GetGlobalComp:k=>k==='monitor'?{GetHeroEid:()=>1}:k==='controller'?controller:null};}
let world=makeWorld();
const ctx={WebSocket:class {constructor(){socket=this;this.readyState=1;}send(v){this.last=JSON.parse(v);}},setTimeout(f,ms){if(ms===1000)f();},Date:{now:()=>clock},
 SceneMgr:{inst:{GetCurSceneType:()=>scene}},CombatMgr:{inst:{GetBattleBySceneType:()=>({_fighting:ready,battleData:{world,CheckCurHeroCreated:()=>ready}}),GetCurRenderSceneType:()=>render}},CombatTPMgr:{inst:{GetIsTPing:()=>teleport}},
 CompEnum:{GMonitor:'monitor',Attr:'attr'},RCompEnum:{RTransform:'rt',GController:'controller'},
 ConfigMgr:{inst:{GetBattleParam:()=>1000,GetKey:()=>({name:'重叠怪物'})}},configTable:{monster_type:1},L:s=>s,CType:{Relationship:{Enemy:2}},
 Utils:{CalcDistance:(a,b)=>Math.hypot(a.x-b.x,a.z-b.z),GetRelationshipWithoutCombat:(h,e)=>e.enemy?2:1,GetPlayerControlHeroAIComp:()=>ai},UtilsInterface:{EntityUtils:{CheckEntityHasDieTypeTag:e=>e.dead}},
 EntityClickHelper:{OnClickMonster(h,e){calls.push(e.eid);controller.curHeroSelectTargetEid=e.eid;}},
 ClientStateSyncUtils:{ResetLocalHeroAISelectTargetEid(){controller.curHeroSelectTargetEid=null;}}
};
vm.runInNewContext(fs.readFileSync('BossAssistant/Resources/Runtime.js','utf8'),ctx);
let id=0;function req(op,fields={}){socket.onmessage({data:JSON.stringify({id:++id,op,...fields})});return socket.last;}
let state=req('targetMode',{enabled:true}).result;
assert.deepEqual(state.rows.map(r=>r.eid),['11','10']);assert.equal(calls.length,0,'Viewing never selects');assert.equal(state.radius,10);
let scope=state.scope;
assert.equal(req('targetSelect',{scope,eid:'10'}).error,undefined);assert.equal(calls.at(-1),10);
state=req('targetTick').result;assert.equal(state.rows.find(r=>r.eid==='10').requested,true);assert.equal(state.rows.find(r=>r.eid==='10').selected,false,'Requested is not reported as applied');
ai.playerSelectedTargetEid=10;assert.equal(req('targetTick').result.rows.find(r=>r.eid==='10').selected,true);
clock+=1000;state=req('targetMode',{enabled:true,autoHighest:true}).result;assert.equal(calls.at(-1),11);assert.equal(state.autoHighest,true);
clock+=1000;a.hp=150;req('targetTick');assert.equal(calls.at(-1),11,'Equal HP keeps current selection');
a.hp=190;clock+=1000;req('targetTick');assert.equal(calls.at(-1),10);
req('targetMode',{enabled:true,autoHighest:false});const count=calls.length;b.hp=195;clock+=1000;req('targetTick');assert.equal(calls.length,count,'Turning automatic selection off stops target switching');
assert.equal(req('targetSelect',{scope,eid:'11'}).result.autoHighest,false,'Explicit manual selection leaves automatic mode');
b.dead=true;assert.match(req('targetSelect',{scope,eid:'11'}).error,/死亡/);
b.dead=false;b.hp=180;clock+=1000;req('targetMode',{enabled:true,autoHighest:true,locked:true});const before=calls.length;req('targetTick',{locked:true});assert.equal(calls.length,before);assert.match(req('targetSelect',{scope,eid:'10'}).error,/保护/);
req('targetTick',{locked:false});world=makeWorld();assert.match(req('targetSelect',{scope,eid:'10'}).error,/场景/);scope=req('targetTick').result.scope;
render=1;assert.equal(req('targetTick').result.ready,false);assert.match(req('targetSelect',{scope,eid:'10'}).error,/场景/);render=2;
teleport=true;assert.equal(req('targetTick').result.ready,false);teleport=false;
hero.dead=true;assert.equal(req('targetTick').result.ready,false);hero.dead=false;
ready=false;assert.equal(req('targetTick').result.ready,false);ready=true;
clock+=1000;req('targetSelect',{scope,eid:'10'});controller.curHeroSelectTargetEid=11;req('targetMode',{enabled:false});assert.equal(controller.curHeroSelectTargetEid,11,'Disabling preserves a later normal game click');
req('targetMode',{enabled:true});req('targetSelect',{scope,eid:'10'});req('targetMode',{enabled:false});assert.equal(controller.curHeroSelectTargetEid,null,'Disabling clears only owned target');
req('targetMode',{enabled:true,autoHighest:true});socket.onclose();assert.equal(req('targetTick').result.enabled,false);assert.equal(req('targetTick').result.autoHighest,false);
console.log('PASS: nearby living enemy monsters only, duplicate names use EIDs, native radius, live HP sort, original click, actual vs requested, highest HP toggle, stable ties, manual override, dead/stale/loading/teleport/account gates, owned cleanup and disconnect');
