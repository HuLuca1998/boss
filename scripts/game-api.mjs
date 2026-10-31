#!/usr/bin/env node
// node scripts/game-api.mjs exploreMap '{"areaId":7}'
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const [op,raw='{}',output]=process.argv.slice(2);
if(!op){console.error('Usage: node scripts/game-api.mjs OP [JSON_FIELDS]');process.exit(2);}
const fields=JSON.parse(raw);
const connection=JSON.parse(fs.readFileSync(path.join(os.homedir(),'Library/Application Support/HeroBossAssistant/Connection.json'),'utf8'));
const socket=new WebSocket(`ws://127.0.0.1:${connection.port}`);
const timeout=setTimeout(()=>{console.error('API response timeout');socket.close();process.exitCode=1;},15000);
socket.onopen=()=>socket.send(JSON.stringify({hello:'yzlm-controller-v1',token:connection.token}));
socket.onmessage=({data})=>{
  const value=JSON.parse(data);
  if(value.hello){socket.send(JSON.stringify({...fields,op,id:1}));return;}
  if(value.id!==1)return;
  clearTimeout(timeout);socket.close();
  if(value.error){console.error(value.error);process.exitCode=1;}
  else if(op==='exploreRender' && output){
    const {dataURL,...metadata}=value.result;
    if(!dataURL?.startsWith('data:image/'))throw Error('Invalid render response');
    fs.writeFileSync(output,Buffer.from(dataURL.slice(dataURL.indexOf(',')+1),'base64'));
    console.log(JSON.stringify({...metadata,path:path.resolve(output)},null,2));
  } else console.log(JSON.stringify(value.result,null,2));
};
socket.onerror=()=>{clearTimeout(timeout);console.error('Cannot connect to 首领助手');process.exitCode=1;};
