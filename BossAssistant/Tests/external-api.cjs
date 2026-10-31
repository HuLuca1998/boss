const {spawn}=require('node:child_process'),assert=require('node:assert/strict');
const p=spawn(process.argv[2],[],{stdio:['ignore','pipe','inherit']});let started=false,finished=false;
async function connect(port,hello,token='external-test-token'){
 const ws=new WebSocket('ws://127.0.0.1:'+port);
 await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true})});
 ws.send(JSON.stringify({hello,token}));return ws;
}
function next(ws){return new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(Error('timeout')),5000);ws.addEventListener('message',b=>{clearTimeout(t);resolve(JSON.parse(b.data))},{once:true})})}
p.stdout.on('data',async b=>{
 const m=b.toString().match(/PORT (\d+)/);if(!m||started)return;started=true;
 try{
  const game=await connect(m[1],'yzlm-native-boss-v2');let gameRequests=0;
  game.addEventListener('message',b=>{const r=JSON.parse(b.data);gameRequests++;game.send(JSON.stringify({id:r.id,result:{echo:r.op,areaId:7}}))});
  const controller=await connect(m[1],'yzlm-controller-v1');let hello=await next(controller);assert.equal(hello.connected,true);
  controller.send(JSON.stringify({id:42,op:'exploreMap'}));let reply=await next(controller);assert.equal(reply.id,42);assert.equal(reply.result.echo,'exploreMap');
  controller.send(JSON.stringify({id:46,op:'exploreState'}));reply=await next(controller);assert.equal(reply.result.echo,'exploreState');
  controller.send(JSON.stringify({id:43,op:'eval',code:'no'}));reply=await next(controller);assert.equal(reply.error,'unsupported_operation');assert.equal(gameRequests,2);
  const other=await connect(m[1],'yzlm-controller-v1');hello=await next(other);assert.equal(hello.connected,true);other.close();
  controller.send(JSON.stringify({id:44,op:'location'}));reply=await next(controller);assert.equal(reply.result.areaId,7);
  const bad=await connect(m[1],'yzlm-controller-v1','wrong');await new Promise(resolve=>bad.addEventListener('close',resolve,{once:true}));
  game.close();await new Promise(resolve=>setTimeout(resolve,80));controller.send(JSON.stringify({id:45,op:'exploreMap'}));reply=await next(controller);assert.match(reply.error,/尚未连接/);
  controller.close();finished=true;console.log('PASS external API auth, controller isolation, operation allowlist, reply correlation, disconnect errors');p.kill();
 }catch(e){console.error(e);p.kill();process.exitCode=1;}
});p.on('exit',()=>{if(!finished)process.exitCode=1});
