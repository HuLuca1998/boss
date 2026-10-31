#!/usr/bin/env node
// Tests the installed app and actual game; movement is explicitly opt-in.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const move=process.argv.includes('--move');
const output=path.resolve(process.argv.find(a=>a.endsWith('.json'))||'analysis/exploration-api/live-audit.json');
const report={at:new Date().toISOString(),movementRequested:move,checks:[],limitations:[]};
function call(op,fields={}){
  try{return JSON.parse(execFileSync(process.execPath,['scripts/game-api.mjs',op,JSON.stringify(fields)],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));}
  catch(e){throw Error(e.stderr?.toString().trim()||e.message);}
}
function check(name,fn){const detail=fn();report.checks.push({name,passed:true,detail});console.log('PASS '+name);return detail;}
function rejected(name,op,fields,pattern){check(name,()=>{assert.throws(()=>call(op,fields),pattern);return 'Rejected by actual runtime';});}
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const distance=(a,b)=>Math.hypot(a.x-b.x,a.z-b.z);
let start;
try{
  const state=call('exploreState');start=state.location.heroPos;
  check('live scene and hero state',()=>{assert.equal(state.location.kind,'wild');assert(state.location.ready);assert.equal(state.nearbyReady,true);assert(state.combat.maxHp>0);assert(state.combat.hp>0&&state.combat.hp<=state.combat.maxHp);return {scriptIdentity:state.scriptIdentity,hp:state.combat.hp,maxHp:state.combat.maxHp,auto:state.combat.auto,enemies:state.enemies.length};});
  const map=call('exploreMap',{includeFog:true});
  check('observed map and fog schema',()=>{assert(map.fields.length);for(const f of map.fields){if(f.fog?.observed){assert(f.fog.bitsPerWord>0);assert.equal(f.fog.words.length*f.fog.bitsPerWord,f.fog.division**2);}}return {areaId:map.areaId,fields:map.fields.length,eventCount:map.fields.reduce((n,f)=>n+f.events.length,0)};});
  const excluded=map.fields.flatMap(f=>f.events).find(e=>e.typeName.includes('方尖碑'));
  if(excluded)rejected('excluded obelisk cannot be followed','exploreFollow',{eventId:excluded.eventId},/event_not_authorized/);
  const done=map.fields.flatMap(f=>f.events).find(e=>e.allowed&&e.done);
  if(done)rejected('completed event cannot be repeated','exploreFollow',{eventId:done.eventId},/event_already_done/);
  const ui=call('exploreUI');
  check('real UI tree',()=>{assert(ui.nodes.length>0);assert.equal(ui.truncated,false);assert(ui.nodes.some(n=>n.hasClick));return {nodes:ui.nodes.length,revision:ui.revision};});
  call('exploreUI');
  rejected('stale snapshot blocks actual click','exploreClick',{revision:ui.revision,nodeId:ui.nodes.find(n=>n.hasClick&&n.mouseEnabled)?.id},/stale_ui_snapshot/);
  rejected('invalid movement blocks actual path request','exploreMove',{x:'invalid',z:0},/invalid_position/);
  const locked=map.areas.find(a=>!a.unlocked);
  if(locked){const lockedMap=call('exploreMap',{areaId:locked.areaId});check('unopened map stays locked',()=>{assert(lockedMap.fields.every(f=>!f.unlocked));return {areaId:locked.areaId,fields:lockedMap.fields.length};});}
  const again=call('exploreState');check('reading and rejected calls do not move or enable combat',()=>{assert(distance(start,again.location.heroPos)<0.2);assert.equal(again.combat.auto,state.combat.auto);assert.equal(again.navigation.singleActive,state.navigation.singleActive);return true;});
  if(move){
    assert.equal(state.combat.auto,false,'Disable auto combat before movement test');assert.equal(state.navigation.singleActive,false,'Stop existing route before test');
    // Known walkable approach immediately south of the currently observed gate.
    assert(distance(start,{x:-9264.3,z:1389.9})<2,'Movement test is scoped to the verified gate approach');
    const target={x:start.x,z:start.z-12};call('exploreMove',target);let samples=[],arrived=false;
    for(let i=0;i<20;i++){await wait(400);const s=call('exploreState');samples.push({position:s.location.heroPos,active:s.navigation.singleActive});if(distance(target,s.location.heroPos)<8){arrived=true;break;}}
    check('real movement changes actual hero position',()=>{assert(arrived);assert(samples.some(s=>distance(start,s.position)>3));return {samples};});
    call('exploreStop');const stopped=call('exploreState');check('stop clears native path and auto combat',()=>{assert.equal(stopped.navigation.singleActive,false);assert.equal(stopped.navigation.wholeActive,false);assert.equal(stopped.combat.auto,false);return true;});
    call('exploreMove',{x:start.x,z:start.z+3});let returned=false;
    for(let i=0;i<20;i++){await wait(400);if(distance(start,call('location').heroPos)<5){returned=true;break;}}
    call('exploreStop');check('returned to gate approach',()=>{assert(returned);return call('location').heroPos;});
  }
  report.limitations.push('New-map gathering/chest/teleport and successful event-follow completion remain untested before opening; no uncompleted authorized event is available in the completed current area.');
  report.limitations.push('Conch render includes UI only; 3D scene needs native window screenshots.');
  report.passed=true;
}catch(e){report.passed=false;report.error=e.message;console.error(e.message);process.exitCode=1;if(move)try{call('exploreStop');}catch{}}
finally{fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log('Report: '+output);}
