const {spawn}=require('child_process');
const WebSocket=require('/opt/homebrew/lib/node_modules/rea-agents/node_modules/ws');
const p=spawn(process.argv[2],[],{stdio:['ignore','pipe','inherit']});let started=false,rejected=false,passed=false;
p.stdout.on('data',b=>{
 const s=b.toString();process.stdout.write(s);
 const m=s.match(/PORT (\d+)/);
 if(m&&!started){started=true;
  const bad=new WebSocket('ws://127.0.0.1:'+m[1]+'/game');
  bad.on('open',()=>bad.send(JSON.stringify({hello:'yzlm-native-boss-v2',token:'invalid'})));
  bad.on('close',()=>{rejected=true;console.log('PASS rejected unauthenticated client');
   const good=new WebSocket('ws://127.0.0.1:'+m[1]+'/game');good.on('open',()=>good.send(JSON.stringify({hello:'yzlm-native-boss-v2',token:'integration-test-token'})));
   good.on('message',b=>{const v=JSON.parse(b);if(v.op!=='list')throw Error('unexpected operation');good.send(JSON.stringify({id:v.id,result:{areaId:6,rows:[]}}));});good.on('error',()=>{});
  });bad.on('error',()=>{});
 }
 if(s.includes('PASS authenticated RPC'))passed=true;
});
p.on('exit',code=>process.exit(code===0&&rejected&&passed?0:1));
