import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
export class GameClient {
  constructor(connectionFile=process.env.BOSS_ASSISTANT_CONNECTION||path.join(os.homedir(),'Library/Application Support/HeroBossAssistant/Connection.json')){
    this.connectionFile=connectionFile;this.socket=null;this.connecting=null;this.sequence=0;this.pending=new Map();
  }
  async connect(){
    if(this.socket?.readyState===WebSocket.OPEN)return;
    if(this.connecting)return this.connecting;
    this.connecting=(async()=>{
      const {port,token}=JSON.parse(await fs.readFile(this.connectionFile,'utf8'));
      if(!Number.isInteger(port)||port<1||port>65535||typeof token!=='string'||!token)throw Error('Invalid local connection settings');
      await new Promise((resolve,reject)=>{
        const ws=new WebSocket(`ws://127.0.0.1:${port}`);let authenticated=false;
        const timer=setTimeout(()=>{reject(Error('Assistant authentication timeout'));ws.close();},5000);
        ws.addEventListener('open',()=>ws.send(JSON.stringify({hello:'yzlm-controller-v1',token})));
        ws.addEventListener('message',({data})=>{
          let v;try{v=JSON.parse(data);}catch{ws.close();return;}
          if(!authenticated){if(v.hello!=='yzlm-controller-v1')return;authenticated=true;clearTimeout(timer);this.socket=ws;resolve();return;}
          const request=this.pending.get(v.id);if(!request)return;this.pending.delete(v.id);clearTimeout(request.timer);
          if(v.error)request.reject(Error(v.error));else request.resolve(v.result);
        });
        const closed=()=>{
          clearTimeout(timer);if(!authenticated)reject(Error('Assistant connection failed'));
          if(this.socket===ws){this.socket=null;for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Assistant disconnected; inspect state before retrying an action'));}this.pending.clear();}
        };
        ws.addEventListener('close',closed);ws.addEventListener('error',closed);
      });
    })();
    try{await this.connecting;}finally{this.connecting=null;}
  }
  async request(op,fields={}){
    await this.connect();const id=++this.sequence;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.pending.delete(id);reject(Error('Game response timeout; inspect state before retrying an action'));},14000);
      this.pending.set(id,{resolve,reject,timer});
      try{this.socket.send(JSON.stringify({...fields,op,id}));}catch(e){clearTimeout(timer);this.pending.delete(id);reject(e);}
    });
  }
  close(){this.socket?.close();}
}
