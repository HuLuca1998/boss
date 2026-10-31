const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
let socket,followed,moved,clicked=0,now=1000;
const configs=[{id:1,type:1,ins_id:10,is_count:1},{id:2,type:2,ins_id:10,is_count:1},{id:3,type:3,ins_id:10,is_count:1},{id:4,type:4,ins_id:20,is_count:1},{id:5,type:4,ins_id:10,is_count:1}];
const labels={1:'采集物',2:'聚魂匣',3:'方尖碑',4:'地图宝箱'};
const stage={width:600,height:800,visible:true,name:'stage',_children:[]};
const button={parent:stage,visible:true,mouseEnabled:true,name:'collect',text:'采集',_children:[],event(){clicked++}};stage._children.push(button);
const wild={GetCurAreaId:()=>7,GetFieldIdsInArea:()=>[1,2],CheckAreaIsUnlock:()=>true,GetFieldIdByInsId:id=>id/10,GetInsIdByFieldId:id=>id*10,GetMapIdByFieldId:id=>id,GetFieldNameByFieldId:id=>'field'+id,CheckFieldIsUnlock:id=>id===1,GetCurFieldId:()=>1,GetFieldCfg:()=>({}),GetAreaNameByAreaId:()=>'',GetCurWildInsId:()=>10};
const model={GetEventTypeName:t=>labels[t],GetOutEventCfgListByInsId:ins=>configs.filter(c=>c.ins_id===ins),GetSimpleEventInfo:(ins,id)=>id===1?{status:3}:null,GetOutEventInfoByEventId:()=>null,GetOutEventPosByEventId:()=>({x:1,y:0,z:2}),CheckOutEventIsCanShowInMap:()=>true,GetCurNormalProgress:()=>50,GetAreaOutEventProgress:()=>({1:[1,2]}),StopWholeMapOutEventFollow(){},StopHideMapOutEventFollow(){},GetFollowParams:()=>null};
const ctx={WebSocket:class{constructor(){socket=this;this.readyState=1;}send(v){this.last=JSON.parse(v)}},setTimeout(fn,ms){if(ms===1000)fn()},Date:{now:()=>now},
 WildIdleModel:{inst:wild},OutEventModel:{inst:model},types:{outevent_status:{got:3}},L:x=>x,
 ConfigMgr:{inst:{GetCfg:()=>({ForEach:fn=>fn({area:7,area_name_show:'测试区'})}),GetKey:(table,id)=>configs.find(c=>c.id===id)}},configTable:{field:1,outevent:2},
 Laya:{stage,Point:class{},Event:class{static CLICK='click';setTo(){}},Vector3:class{constructor(x,y,z){Object.assign(this,{x,y,z})}}},
 MapPathMgr:{inst:{CheckIsMapReachable:(x,z)=>x<100}},
 EventFollowMgr:{inst:{ShowEventFollowByOutEventId:id=>followed=id,ShowEventFollowByParams:p=>moved=p.pos}},
};
let source=fs.readFileSync('BossAssistant/Resources/Runtime.js','utf8');
// Keep the actual dispatch functions; isolate existing scene policy for this unit test.
source=source.replace('  function dispatch(m) {','  locationSnapshot=function(){return {kind:"wild"}};requireHuntScene=function(){};\n  function dispatch(m) {');
vm.runInNewContext(source,ctx);
function call(op,fields={}){socket.onmessage({data:JSON.stringify({op,id:1,...fields})});return socket.last;}
let r=call('exploreMap');assert(!r.error,r.error);assert.equal(r.result.fields.length,2);assert.equal(r.result.fields[0].events[0].done,true);assert.equal(r.result.fields[0].events[1].observed,false);assert.equal(r.result.fields[0].events[1].done,false);assert.equal(r.result.fields[0].events[1].allowed,false);
assert.match(call('exploreFollow',{eventId:2}).error,/not_authorized/);assert.match(call('exploreFollow',{eventId:3}).error,/not_authorized/);assert.match(call('exploreFollow',{eventId:1}).error,/already_done/);assert.match(call('exploreFollow',{eventId:4}).error,/field_locked/);assert.equal(followed,undefined);
assert.equal(call('exploreFollow',{eventId:5}).result.completed,false);assert.equal(followed,5);
assert.equal(call('exploreMove',{x:2,z:3}).result.requested,true);assert.equal(moved.x,2);assert.match(call('exploreMove',{x:101,z:3}).error,/unreachable/);
r=call('exploreUI');assert(!r.error,r.error);let revision=r.result.revision;
assert.equal(call('exploreClick',{revision,nodeId:'2'}).result.requested,true);assert.equal(clicked,1);assert.match(call('exploreClick',{revision,nodeId:'2'}).error,/stale/);
r=call('exploreUI');revision=r.result.revision;button.visible=false;assert.match(call('exploreClick',{revision,nodeId:'2'}).error,/not_visible/);button.visible=true;
r=call('exploreUI');now+=11000;assert.match(call('exploreClick',{revision:r.result.revision,nodeId:'2'}).error,/stale/);
assert.match(call('exploreMove',{x:'bad',z:1}).error,/invalid_position/);
console.log('PASS exploration map status, excluded events, locked fields, stale/hidden UI, movement validation');
