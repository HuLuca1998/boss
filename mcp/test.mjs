import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {InMemoryTransport} from '@modelcontextprotocol/sdk/inMemory.js';
import {createServer} from './server.mjs';
const calls=[];let tick=0;
const state=()=>({at:++tick,location:{kind:'wild',name:'test',heroPos:{x:tick,y:0,z:2},gameTime:tick},combat:{hp:100,maxHp:100,auto:false},enemies:[],navigation:{singleActive:false},locked:false});
const game={async request(op,fields){calls.push({op,fields});if(op==='exploreState')return state();if(op==='exploreRender')return {dataURL:'data:image/jpeg;base64,/9j/2Q==',width:1,height:1};if(op==='exploreFollow')throw Error('event_not_authorized');return {requested:true,op};}};
const server=createServer(game),client=new Client({name:'test',version:'1'});
const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await client.connect(b);
try{
 const listed=await client.listTools();assert.equal(listed.tools.length,9);assert(listed.tools.find(t=>t.name==='game_state').annotations.readOnlyHint);assert.equal(listed.tools.find(t=>t.name==='game_move').annotations.readOnlyHint,false);
 assert.equal((await client.callTool({name:'game_map',arguments:{areaId:7}})).structuredContent.op,'exploreMap');
 let r=await client.callTool({name:'game_move',arguments:{x:1,z:2}});assert.equal(r.structuredContent.requested,true);assert.equal(calls.at(-1).fields.x,1);
 r=await client.callTool({name:'game_move',arguments:{x:'bad',z:2}});assert.equal(r.isError,true);assert.equal(calls.at(-1).fields.x,1);
 r=await client.callTool({name:'game_follow',arguments:{eventId:1}});assert.equal(r.isError,true);assert.match(r.content[0].text,/not_authorized/);
 r=await client.callTool({name:'game_render',arguments:{}});assert.equal(r.content[0].type,'image');assert.equal(r.content[0].mimeType,'image/jpeg');
 const progress=[];r=await client.callTool({name:'game_watch',arguments:{seconds:1,intervalMs:500}},undefined,{onprogress:p=>progress.push(p)});assert(r.structuredContent.changes.length>=2);assert(progress.length>=2);assert(progress[1].progress>progress[0].progress);
 assert((await client.readResource({uri:'game://exploration/guide'})).contents[0].text.includes('聚魂匣'));
 console.log('PASS MCP negotiation, schemas, native RPC routing, read/write annotations, errors, image content, streamed progress and guide resource');
}finally{await client.close();await server.close();}
