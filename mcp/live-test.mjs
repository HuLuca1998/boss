import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const bundle=process.argv[2]||'/Applications/首领助手.app/Contents/Resources/ExplorationMCP.mjs';
const client=new Client({name:'live-verification',version:'1.4.7'}),transport=new StdioClientTransport({command:process.execPath,args:[bundle],stderr:'inherit'});
const report={at:new Date().toISOString(),bundle,checks:[]};
try{
 await client.connect(transport);const tools=await client.listTools();assert.equal(tools.tools.length,9);report.checks.push('9 tools negotiated over real stdio');
 const map=await client.callTool({name:'game_map',arguments:{areaId:7,includeFog:true}});assert(!map.isError);assert.equal(map.structuredContent.areaId,7);assert(map.structuredContent.fields.length);report.checks.push('Actual game map through MCP');
 const state=await client.callTool({name:'game_state',arguments:{}});assert(!state.isError,JSON.stringify(state));assert(state.structuredContent.combat.hp>0);report.checks.push('Actual hero and native navigation state');
 const ui=await client.callTool({name:'game_ui',arguments:{}});assert(!ui.isError);assert(ui.structuredContent.nodes.length>0);report.checks.push('Actual game UI tree');
 const render=await client.callTool({name:'game_render',arguments:{}});assert(!render.isError);assert.equal(render.content[0].type,'image');assert(Buffer.from(render.content[0].data,'base64').length>100);report.checks.push('Actual JPEG returned as MCP image');
 const notifications=[];const watch=await client.callTool({name:'game_watch',arguments:{seconds:2,intervalMs:500}},undefined,{onprogress:p=>notifications.push(p)});assert(!watch.isError);assert(watch.structuredContent.samples>=2);assert(notifications.length>=1);report.checks.push('Bounded real sampling and progress notification');
 report.watch={samples:watch.structuredContent.samples,changes:watch.structuredContent.changes.length,notifications:notifications.length};
 const bad=await client.callTool({name:'game_move',arguments:{x:'bad',z:0}});assert.equal(bad.isError,true);report.checks.push('Invalid movement rejected without game mutation');report.passed=true;
 console.log(JSON.stringify(report,null,2));
}catch(e){report.passed=false;report.error=e.message;console.error(e);process.exitCode=1;}
finally{fs.mkdirSync('analysis/exploration-api',{recursive:true});fs.writeFileSync('analysis/exploration-api/mcp-live-audit.json',JSON.stringify(report,null,2)+'\n');await client.close();}
