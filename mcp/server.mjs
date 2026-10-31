import {McpServer} from '@modelcontextprotocol/sdk/server/mcp.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {z} from 'zod';
import {GameClient} from './game-client.mjs';
export const instructions='Use game_state and game_map before acting; read fresh UI and identify a button by its text and ancestors before game_click. requested=true is not completion. Verify actual position, enemy HP, event done and counts after every action. Unobserved data is unknown. Never act on 方尖碑 or 聚魂匣 for the current exploration task. Stop on account protection. Do not purchase, share, or spend paid resources. The engine render contains UI only; use native window screenshots for 3D. game_watch observes changes for a bounded interval; it does not automate exploration or stop movement when cancelled.';
export function createServer(game=new GameClient()){
  const server=new McpServer({name:'boss-assistant',version:'1.4.7'},{instructions});
  const result=value=>({content:[{type:'text',text:JSON.stringify(value)}],structuredContent:value});
  const safe=fn=>async(...args)=>{try{return await fn(...args);}catch(e){return {isError:true,content:[{type:'text',text:e.message}]};}};
  function register(name,description,inputSchema,op,readOnly=true){
    server.registerTool(name,{description,inputSchema,annotations:{readOnlyHint:readOnly,destructiveHint:false,idempotentHint:readOnly,openWorldHint:false}},safe(async fields=>result(await game.request(op,fields))));
  }
  register('game_map','Read regions, submaps, event IDs/positions/completion, prerequisites and optionally observed fog. Locked/unobserved maps are not explored.',{areaId:z.number().int().positive().optional(),includeFog:z.boolean().optional()},'exploreMap');
  register('game_state','Read actual scene, hero HP/death/auto battle, nearby enemy IDs/HP/positions, and native navigation status. No target selection or movement.',{},'exploreState');
  register('game_ui','Read visible UI tree with text, parent IDs, clickable nodes and revision. IDs expire in10 seconds or after another UI read/click.',{},'exploreUI');
  register('game_move','Request native movement to world x,z. Observe actual position with game_state/game_watch to confirm; no teleport bypass.',{x:z.number().finite(),z:z.number().finite()},'exploreMove',false);
  register('game_follow','Follow an authorized gathering/chest/teleport/monster-group/pollution event using native game routing; refuses completed, locked or excluded events.',{eventId:z.number().int().positive()},'exploreFollow',false);
  register('game_click','Click a node from the latest UI snapshot, after checking text and ancestors; preserve native button checks. Never blindly confirm purchases or excluded activities.',{revision:z.number().int().nonnegative(),nodeId:z.string().min(1)},'exploreClick',false);
  register('game_stop','Stop native single-event/whole-map routing and wild auto battle, then read game_state to verify.',{},'exploreStop',false);
  server.registerTool('game_render',{description:'Read engine UI render as an MCP JPEG image; 3D scene can be black. Use native window screenshot for full3D.',inputSchema:{},annotations:{readOnlyHint:true,openWorldHint:false}},safe(async()=>{
    const {dataURL,...metadata}=await game.request('exploreRender');
    if(!dataURL?.startsWith('data:image/jpeg;base64,'))throw Error('Unexpected game render format');
    return {content:[{type:'image',mimeType:'image/jpeg',data:dataURL.slice(dataURL.indexOf(',')+1)},{type:'text',text:JSON.stringify(metadata)}]};
  }));
  server.registerTool('game_watch',{description:'Observe state changes for up to30 seconds. Sends MCP progress notifications when supported and returns actual changed snapshots. This watches; it never moves or attacks.',inputSchema:{seconds:z.number().int().min(1).max(30).default(5),intervalMs:z.number().int().min(500).max(5000).default(1000)},annotations:{readOnlyHint:true,openWorldHint:false}},safe(async({seconds,intervalMs},extra)=>{
    const until=Date.now()+seconds*1000,changes=[];let previous='',samples=0;
    do{
      if(extra.signal.aborted)throw Error('Observation cancelled; movement is unaffected. Use game_stop if needed.');
      const state=await game.request('exploreState');samples++;
      const signature=JSON.stringify({location:{...state.location,gameTime:null},combat:state.combat,enemies:state.enemies,navigation:state.navigation,locked:state.locked});
      if(signature!==previous){previous=signature;changes.push(state);
        if(extra._meta?.progressToken!==undefined)await extra.sendNotification({method:'notifications/progress',params:{progressToken:extra._meta.progressToken,progress:samples,message:`${state.location.name||state.location.kind}; HP ${state.combat.hp}/${state.combat.maxHp}; enemies ${state.enemies.length}; routing ${state.navigation.singleActive}`}});
      }
      const delay=Math.min(intervalMs,until-Date.now());if(delay<=0)break;
      await new Promise((resolve,reject)=>{const abort=()=>{clearTimeout(timer);reject(Error('Observation cancelled'));};const timer=setTimeout(()=>{extra.signal.removeEventListener('abort',abort);resolve();},delay);extra.signal.addEventListener('abort',abort,{once:true});});
    }while(Date.now()<until);
    return result({samples,changes,completed:true});
  }));
  server.registerResource('exploration-guide','game://exploration/guide',{mimeType:'text/plain',description:'Current exploration constraints and confirmation workflow'},async uri=>({contents:[{uri:String(uri),mimeType:'text/plain',text:instructions}]}));
  return server;
}
if(process.argv[1] && /(?:server|ExplorationMCP)\.mjs$/.test(process.argv[1])){
  const game=new GameClient(),server=createServer(game);
  await server.connect(new StdioServerTransport());
  process.stdin.on('end',()=>game.close());
  process.on('SIGTERM',()=>{game.close();process.exit(0);});
}
