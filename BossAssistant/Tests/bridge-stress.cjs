const {spawn}=require('node:child_process');
const WebSocket=require('/opt/homebrew/lib/node_modules/rea-agents/node_modules/ws');
const child=spawn(process.argv[2],[],{stdio:['ignore','pipe','inherit']});let started=false,passed=false;
child.stdout.on('data',data=>{
 const line=data.toString();process.stdout.write(line);
 const match=line.match(/PORT (\d+)/);
 if(match&&!started){started=true;const socket=new WebSocket('ws://127.0.0.1:'+match[1]+'/game');
  socket.on('open',()=>socket.send(JSON.stringify({hello:'yzlm-native-boss-v2',token:'stress-test-token'})));
  socket.on('message',data=>{const value=JSON.parse(data);if(value.op==='drop'){socket.close();return;}if(socket.readyState===1)socket.send(JSON.stringify({id:value.id,result:{value:value.value}}));});socket.on('error',()=>{});
 }
 if(line.includes('PASS 2000'))passed=true;
});
child.on('exit',code=>process.exit(code===0&&passed?0:1));
