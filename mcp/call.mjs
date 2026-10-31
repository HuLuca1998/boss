#!/usr/bin/env node
// Protocol-level client fallback when the current chat has not refreshed MCP tools yet.
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import fs from 'node:fs';
const [name,raw='{}',imageOutput]=process.argv.slice(2);if(!name)throw Error('Usage: node mcp/call.mjs TOOL [JSON] [IMAGE_OUTPUT]');
const transport=new StdioClientTransport({command:process.execPath,args:['/Applications/首领助手.app/Contents/Resources/ExplorationMCP.mjs'],stderr:'inherit'});
const client=new Client({name:'boss-assistant-local-client',version:'1.4.7'});
try{
 await client.connect(transport);
 const response=await client.callTool({name,arguments:JSON.parse(raw)},undefined,{timeout:60000,onprogress:p=>console.error(p.message)});
 for(const item of response.content||[]){
  if(item.type==='image'){
   if(!imageOutput)throw Error('Provide IMAGE_OUTPUT for image tools');
   fs.writeFileSync(imageOutput,Buffer.from(item.data,'base64'));console.log(JSON.stringify({image:imageOutput,mimeType:item.mimeType}));
  }else if(item.type==='text')console.log(item.text);
 }
 if(response.isError)process.exitCode=1;
}finally{await client.close();}
