(function () {
  var socket, stopped = false, navigation = null, priorAuto = null, targetedAreaBosses={};
  var keyboard = {enabled:false,pressed:{},eventCount:0,lastEvent:null,lastNativeAt:0};
  var originalHasKeyDown=null, keyboardInstalled=false, escapeHeld=false;
  function escapeBack(){
    if(typingText())return {closed:false,reason:'typing'};
    var mgr=UIMgr.inst,map=mgr._openViews,top=null,order=-Infinity,ambiguous=false;
    if(!map || !map.forEach || typeof mgr.GetOpenViewOrder!=='function')return {closed:false,reason:'unavailable'};
    map.forEach(function(v){
      if(!v || !v.gameObject || !v.gameObject.visible || v.gameObject.destroyed || typeof v.Layer!=='function')return;
      // Passive toast/damage/reward tickers are also excluded by the game's own view stack checks.
      if(['NotifyMsgView','NotifyLongMsgView','NotifyScoreUpView','DropItemNotifyView','NotifyTaskUpView'].indexOf(v.viewName || (v.viewVo && v.viewVo.name))>=0)return;
      if(['MiddleLayer','HighLayer','TopLayer'].indexOf(v.Layer())<0)return;
      var n=mgr.GetOpenViewOrder(v);if(!Number.isFinite(n))return;
      if(n>order){top=v;order=n;ambiguous=false;}else if(n===order)ambiguous=true;
    });
    if(!top || ambiguous)return {closed:false,reason:'no_safe_top_view'};
    var cfg=top.viewVo,sub=null,action=null;
    if(!cfg || mgr.GetView(cfg.id)!==top)return {closed:false,reason:'stale'};
    // Only original return handlers. Never invoke confirmation, purchase or claim handlers.
    var returnFrames=[];
    Object.keys(top).slice(0,300).forEach(function(k){
      var d=Object.getOwnPropertyDescriptor(top,k),s=d && d.value;
      if(!s)return;
      var known=(typeof CommonTab2SubView!=='undefined' && s instanceof CommonTab2SubView && s.OncloseBtnClick===CommonTab2SubView.prototype.OncloseBtnClick) ||
        (typeof CommonTab3SubView!=='undefined' && s instanceof CommonTab3SubView && s.OncloseBtnClick===CommonTab3SubView.prototype.OncloseBtnClick) ||
        (typeof CommonBg3SubView!=='undefined' && s instanceof CommonBg3SubView && s.OncloseBtnClick===CommonBg3SubView.prototype.OncloseBtnClick) ||
        (typeof CommonBg2SubView!=='undefined' && s instanceof CommonBg2SubView && s.rootView===top && s.OncloseBtnClick===CommonBg2SubView.prototype.OncloseBtnClick);
      if(known && s.baseView===top && !s._closeCb && returnFrames.indexOf(s)<0)returnFrames.push(s);
    });
    if(returnFrames.length===1){sub=returnFrames[0];action=function(){sub.OncloseBtnClick();};}
    if(!action && typeof LotteryShopView!=='undefined' && top instanceof LotteryShopView && top.OncloseBtnClick===LotteryShopView.prototype.OncloseBtnClick)action=function(){top.OncloseBtnClick();};
    if(!action){sub=commonBackgroundClose(top);if(sub)action=function(){sub.OncloseBtnClick();};}
    if(!action && cfg.mask===2 && typeof BaseView!=='undefined' && top.OnMaskBgClick===BaseView.prototype.OnMaskBgClick)action=function(){top.OnMaskBgClick();};
    if(!action)return {closed:false,reason:'unsupported',viewId:cfg.id};
    action();return {closed:true,viewId:cfg.id};
  }
  function typingText() {
    var focus=Laya.stage && Laya.stage.focus;
    return UIMgr.inst.IsOpen(1007) || !!(focus && Laya.Input && focus instanceof Laya.Input);
  }
  function clearArrowKeys(){keyboard.pressed={};}
  function keyboardEvent(e,down){
    var code=e.keyCode || (e.nativeEvent && e.nativeEvent.keyCode);
    if(!Number.isFinite(code) || code<37 || code>40 || !keyboard.enabled)return;
    keyboard.eventCount++;keyboard.lastEvent={code:code,down:down,time:Date.now()};
    if(typingText()){clearArrowKeys();return;}
    if(down)keyboard.pressed[code]=true;else delete keyboard.pressed[code];
    if(e.nativeEvent && e.nativeEvent.preventDefault)e.nativeEvent.preventDefault();
  }
  function installKeyboard(){
    if(keyboardInstalled)return;
    if(!Laya.stage || !Laya.InputManager || typeof Laya.InputManager.hasKeyDown!=='function')throw Error('game_not_ready');
    originalHasKeyDown=Laya.InputManager.hasKeyDown;
    Laya.stage.on(Laya.Event.KEY_DOWN,keyboard,function(e){keyboardEvent(e,true);});
    Laya.stage.on(Laya.Event.KEY_UP,keyboard,function(e){keyboardEvent(e,false);});
    Laya.stage.on(Laya.Event.BLUR,keyboard,clearArrowKeys);
    if(typeof window!=='undefined' && window.addEventListener)window.addEventListener('blur',clearArrowKeys);
    Laya.InputManager.hasKeyDown=function(code){
      if(keyboard.lastNativeAt && Date.now()-keyboard.lastNativeAt>900)clearArrowKeys();
      if(keyboard.enabled && !typingText()) {
        var arrow={87:38,83:40,65:37,68:39}[code];
        if(arrow && keyboard.pressed[arrow])return true;
      }
      return originalHasKeyDown.apply(this,arguments);
    };
    keyboardInstalled=true;
  }
  function keyboardStatus(){return {sceneType:typeof SceneMgr!=='undefined' ? SceneMgr.inst.GetCurSceneType() : null,enabled:keyboard.enabled,pressed:Object.keys(keyboard.pressed).map(Number),eventCount:keyboard.eventCount,lastEvent:keyboard.lastEvent,escape:keyboard.lastEscape||null};}
  function locationSnapshot() {
    var type=SceneMgr.inst.GetCurSceneType();
    var battle=CombatMgr.inst.GetBattleBySceneType(type);
    var data=battle && battle.battleData, world=data && data.world;
    var wild=type===Scene.SceneType.Wild || type===Scene.SceneType.WildSync;
    var init=world && world.battleInitData;
    var dungeonId=init && init.dungeon_id || null;
    var ready=!!(battle && battle._fighting && data && data.world && data.CheckCurHeroCreated() && CombatMgr.inst.GetCurRenderSceneType()===type);
    var pos=ready && data.GetHeroPos ? data.GetHeroPos() : null;
    var fieldId=WildIdleModel.inst.GetCurFieldId();
    var field=wild && fieldId ? WildIdleModel.inst.GetFieldCfg(fieldId) : null;
    var cfg=!wild && dungeonId ? ConfigMgr.inst.GetKey(configTable.instance,dungeonId,false) : null;
    var names={2:'副本',4:'团队副本',6:'高难团队副本',7:'联盟副本',9:'联盟战场',10:'时空裂隙',11:'神器宝库',12:'副本',13:'庆典副本',14:'数字门挑战',15:'爆竹战斗',16:'英雄狩猎'};
    return {kind:wild ? 'wild' : type>0 ? 'dungeon' : 'loading',sceneType:type,
      name:wild ? (field ? L(field.field_name) : '野外加载中') : (cfg && cfg.inst_name ? L(cfg.inst_name) : names[type] || '场景加载中'),
      ready:ready,
      gameTime:world && world.GetGameTime ? world.GetGameTime() : null,dungeonId:dungeonId,heroPos:pos ? {x:pos.x,y:pos.y,z:pos.z} : null};
  }
  function teamFollowing(){
    return typeof WildModel!=='undefined' && typeof WildModel.inst.CheckIsWildSync==='function' && WildModel.inst.CheckIsWildSync() && !WildModel.inst.IsWildSyncLeader();
  }
  function changeOwnedAuto(enabled){
    if(!teamFollowing())WildModel.inst.ChangeAutoSkill(enabled);
  }
  function currentWildData(){
    var type=SceneMgr.inst.GetCurSceneType();
    if(type!==Scene.SceneType.Wild && type!==Scene.SceneType.WildSync)return null;
    var battle=CombatMgr.inst.GetBattleBySceneType(type);return battle && battle.battleData;
  }
  function clearOwnedPath(){
    if(!navigation || !navigation.ownsPath)return;
    var data=currentWildData();
    if(data && data===navigation.pathData && typeof data.ClearClientHeroPathInfo==='function')data.ClearClientHeroPathInfo(true);
    navigation.ownsPath=false;
  }
  function beginBossRoute(route,params){
    var bountyActive=false,paused=false;
    try{bountyActive=typeof BountyTaskModel!=='undefined' && BountyTaskModel.inst.GetAutoBountyStatus()===types.bounty_task.helper_status.action;paused=typeof AutoBountyTaskMgr!=='undefined' && AutoBountyTaskMgr.inst.isClientAutoBountyPause===true;}catch(e){}
    if(bountyActive && !paused){route.phase='blocked';route.error='游戏内悬赏助手正在运行';return;}
    EventFollowMgr.inst.ShowEventFollowByParams(params);
    if(bountyActive && paused){
      var data=currentWildData(),pos=data && data.GetHeroPos();
      if(!pos || typeof data.SetClientHeroPathInfo!=='function' || typeof QVector3==='undefined'){route.phase='blocked';route.error='普通移动接口尚未就绪';return;}
      var path=MapPathMgr.inst.DoubleAStar(pos,params.pos,undefined,false,5000,true);
      if(!Array.isArray(path) || !path.length){route.phase='blocked';route.error='目标位置没有可用路径';return;}
      route.mode='pausedBountyPath';route.pathData=data;route.ownsPath=true;
      data.SetClientHeroPathInfo(path.map(function(p){return new QVector3(p.x*100,0,p.z*100);}),true);
      route.phase='moving';route.target={x:params.pos.x,y:params.pos.y,z:params.pos.z};
      changeOwnedAuto(true);
    }else{
      var accepted=typeof OutEventSingleRouteModel!=='undefined' && OutEventSingleRouteModel.inst.IsInSingleOutEventRouting();
      route.phase=accepted ? 'moving' : 'blocked';
      if(accepted)changeOwnedAuto(true);
      if(!accepted)route.error='游戏未接受自动寻路';
    }
  }
  function observeBossRoute(){
    if(!navigation || !navigation.ownsPath)return;
    var data=currentWildData();if(!data || data!==navigation.pathData)return;
    var pos=data.GetHeroPos(),target=navigation.target;
    if(pos && target){
      var dx=pos.x-target.x,dz=pos.z-target.z;navigation.distance=Math.sqrt(dx*dx+dz*dz);
      if(navigation.distance<=8){clearOwnedPath();navigation.phase='attacking';changeOwnedAuto(true);}
    }
  }
  function suspendHunt() {
    clearOwnedPath();navigation=null;priorAuto=null;
    EventFollowMgr.inst.ClearTargetSceneEventFollow(Scene.SceneType.Wild);
    return {paused:true};
  }
  function requireHuntScene(areaId) {
    if(assist.locked)throw Error('account_recovery_locked');
    if(teamFollowing())throw Error('team_following');
    var location=locationSnapshot();
    if(location.kind!=='wild' || !location.ready || CombatTPMgr.inst.GetIsTPing() || (areaId && areaId!==WildIdleModel.inst.GetCurAreaId()))throw Error('hunt_scene_unavailable');
  }
  function snapshot() {
    var area = WildIdleModel.inst.GetCurAreaId();
    if (!area) throw Error('game_not_ready');
    var location=locationSnapshot();
    if(!location.ready)throw Error('game_not_ready');
    if(navigation && (location.kind==='dungeon' || (area && navigation.areaId!==area)))suspendHunt();
    observeBossRoute();
    var areaKey=null;
    try{if(typeof AreaBossModel!=='undefined'){var keyId=AreaBossModel.inst.boxKeyItemId,keyCount=AreaBossModel.inst.GetTodayRewardTimes();if(Number.isInteger(keyId) && Number.isFinite(keyCount))areaKey={itemId:keyId,count:keyCount,limit:AreaBossModel.inst.boxKeyDayLimit||null};}}catch(e){}
    var raw = WildModel.inst.insId2WildReviveInfoMap;
    var now = Time.GetServerTime();
    var rows = (area ? MapModel.inst.GetMonsterItemDataListByAreaId(area, true, false, true) : []).map(function (b) {
      var cfg = ConfigMgr.inst.GetKey(configTable.monster_type, b.bossId);
      var received = !!(raw && raw.has(b.insId));
      var info = received ? raw.get(b.insId) : null;
      var item = info && Array.isArray(info.info) ? info.info.find(function (p) { return p.point_id === b.pointId; }) : null;
      var cd = received ? MapModel.inst.GetWildPointCD(b.insId, b.pointIndex) : null;
      var areaBoss=b.monsterType===3,areaInfo=null,areaAlive=false;
      if(areaBoss){
        try{areaInfo=AreaBossModel.inst.GetAreaBossInfo(b.insId,b.pointId);}catch(e){}
        received=!!areaInfo;info=areaInfo;item=areaInfo;
        areaAlive=!!(areaInfo && typeof types!=='undefined' && types.area_boss && types.area_boss.status && areaInfo.status===types.area_boss.status.alive);
        var revive=areaInfo && areaInfo.revive_time;
        if(typeof revive==='string' && /^\d+(\.\d+)?$/.test(revive))revive=Number(revive);
        // Alive state is authoritative. Living bosses may omit revive_time entirely,
        // or retain the previous cycle's future timestamp in cached data.
        cd=areaAlive ? 0 : Number.isFinite(revive) && revive>0 ? Math.max(0,revive-now) : null;
      }
      var forbidden=WildModel.inst.insId2ForbidMonPointMap;
      var blocked=!!(forbidden && forbidden.has(b.insId) && forbidden.get(b.insId).includes(b.pointId));
      var alive=!areaBoss || areaAlive;
      return {kind:areaBoss ? 'areaBoss' : 'normal',keyItemId:areaBoss && areaKey ? areaKey.itemId : null,keyCount:areaBoss && areaKey ? areaKey.count : null,monsterType:b.monsterType||2,name:L(cfg.name), bossId:b.bossId, insId:b.insId, mapId:b.mapId,
        pointId:b.pointId, pointIndex:b.pointIndex, uid:b.uid, loaded:received,
        reviveTime:item ? item.revive_time : null, cdSeconds:cd, blocked:blocked,
        areaStatus:areaInfo ? areaInfo.status : null,status:!received || !Number.isFinite(cd) ? 'unknown' : blocked ? 'blocked' : cd > 0 ? 'cooldown' : !alive ? 'unknown' : 'ready'};
    });
    var battle=CombatMgr.inst.GetWildBattleData() || CombatMgr.inst.GetWildSyncBattleData();
    var hero=battle && battle.GetWildHeroPos ? battle.GetWildHeroPos() : null;
    var follow=EventFollowMgr.inst.GetEventFollowVo(Scene.SceneType.Wild);
    var grouped={};
    ConfigMgr.inst.GetCfg(configTable.field).GetCfgList().forEach(function(f){if(!grouped[f.area])grouped[f.area]={id:f.area,name:L(f.area_name_show),unlocked:WildIdleModel.inst.CheckAreaIsUnlock(f.area),current:f.area===area};});
    var fieldCfg=WildIdleModel.inst.GetCurFieldId() ? WildIdleModel.inst.GetFieldCfg(WildIdleModel.inst.GetCurFieldId()) : null;
    return {scriptIdentity:'__CODEX_SCRIPT_ID__',runtimeVersion:3,areaBossKey:areaKey,areaBossVersion:1,location:location,areaName:area ? WildIdleModel.inst.GetAreaNameByAreaId(area) : null,fieldName:fieldCfg ? L(fieldCfg.field_name) : null,areas:Object.keys(grouped).map(function(k){return grouped[k];}).sort(function(a,b){return a.id-b.id;}), areaId:area || 0, fieldId:WildIdleModel.inst.GetCurFieldId(), serverTime:now, navigation:navigation ? {areaId:navigation.areaId,bossId:navigation.bossId,insId:navigation.insId,pointId:navigation.pointId,phase:navigation.phase,mode:navigation.mode||'singleRoute',error:navigation.error||null,target:navigation.target,distance:navigation.distance} : null,
      isTeleporting:CombatTPMgr.inst.GetIsTPing(), followUid:follow ? follow.GetUid() : null,
      heroPos:hero ? {x:hero.x,y:hero.y,z:hero.z} : null, keyboard:keyboardStatus(), rows:rows};
  }
  // Passive event observation only: no frame, login-handler or notification hooks.
  var assist={session:String(Date.now())+'-'+Math.random().toString(36).slice(2),seq:0,args:null,token:null,lastLogin:null,replacedEvents:[],listening:false,locked:false,packets:[],attempted:{},claimed:0,confirmations:0,lastScan:0,lastAction:0,lastClaim:0,redPacketsEnabled:false,fastEnabled:false,fastTimer:false};
  function assistListen(){
    if(assist.listening || typeof EventMgr==='undefined' || typeof ChatDefine==='undefined' || typeof LoginEvent==='undefined')return;
    EventMgr.AddEvent(LoginEvent.OnLoginS2C,assist,function(e){assist.lastLogin={code:e&&e.result,time:Date.now(),token:assist.session+':login:'+(++assist.seq)};if(e && e.result===200104){assist.replacedEvents.push({token:assist.lastLogin.token,time:assist.lastLogin.time});if(assist.replacedEvents.length>20)assist.replacedEvents.shift();}});
    EventMgr.AddEvent(ChatDefine.ChatEvent.ReceiveOneMsg,assist,function(e){assistMessage(e&&e.data,true);});
    assist.listening=true;
  }
  function assistMessage(m,live){
    if(!m || [1000,1004].indexOf(m.channel_id)<0 || m.type!==8 || typeof m.message!=='string')return;
    var p=ChatModel.inst.SplitRedPacketMessage(m.message);
    if(!p.id || !p.hongbaoMainId || !Number.isFinite(p.expiredTimeStamp) || p.expiredTimeStamp<=Time.GetServerTime())return;
    var key=m.channel_id+':'+String(m.session_id)+':'+String(p.id);
    if(assist.packets.some(function(x){return x.key===key;}))return;
    if(assist.packets.length>=200)assist.packets.shift();
    assist.packets.push({key:key,id:p.id,channel:m.channel_id,session:m.session_id,type:p.hongbaoMainId,seenAt:Date.now(),expires:p.expiredTimeStamp,state:'new',attempts:0,checked:0,sent:0,fast:live===true && assist.fastEnabled});
    if(live===true)assistFastPump();
  }
  function assistScan(){
    if(typeof ChatModel==='undefined' || Date.now()-assist.lastScan<5000)return;
    assist.lastScan=Date.now();
    Object.keys(assist.attempted).forEach(function(k){if(assist.attempted[k]<=Time.GetServerTime())delete assist.attempted[k];});
    // Inspect existing caches only; do not open/read-mark sessions or fetch private chat.
    var map=ChatModel.inst._chatDataMap;
    if(map && map.forEach)map.forEach(function(sessions,channel){
      if([1000,1004].indexOf(channel)<0 || !sessions || !sessions.forEach)return;
      sessions.forEach(function(messages){if(Array.isArray(messages))messages.slice(-100).forEach(assistMessage);});
    });
  }
  function assistDialog(){
    if(typeof UIMgr==='undefined' || !UIMgr.inst || typeof UIMgr.inst.GetView!=='function')return null;
    // Any other open modal blocks unattended confirmation.
    var ids=[1183,1137,1004],view=null,id=null;
    for(var i=0;i<ids.length;i++){var v=UIMgr.inst.GetView(ids[i]);if(v && v.gameObject && v.gameObject.visible && !v.gameObject.destroyed){if(view)return null;view=v;id=ids[i];}}
    if(!view || !view.args)return null;
    var a=view.args,text=String(a.content||'');
    if(assist.args!==a){assist.args=a;assist.token=assist.session+':'+(++assist.seq);}
    var pipeline=typeof LoginModel!=='undefined' && LoginModel.inst.loginPipeline;
    var step=pipeline && pipeline.defaultFailStep;
    var active=!!(step && pipeline.curSteps && pipeline.curSteps.has(step));
    var retry=active && typeof a.confirmFun==='function' && a.confirmFun.name==='bound Retry' && !a.cancelFun;
    var h5=typeof SDKMgr!=='undefined' && SDKMgr.inst.CheckIsH5ByConfig();
    var replaced=text==='您的账号已在别处登录' || text==='账号正在别处游戏中，无法退出，本次登录失败，请稍后再试' || (assist.lastLogin && assist.lastLogin.code===200104 && Date.now()-assist.lastLogin.time<90000 && text===L('login_txt_13'));
    var kind=replaced ? 'replaced' : [L('login_txt_14'),L('login_txt_21')].indexOf(text)>=0 ? 'network' : 'unknown';
    return {id:id,token:replaced && text!=='账号正在别处游戏中，无法退出，本次登录失败，请稍后再试' && assist.lastLogin && assist.lastLogin.code===200104 && Date.now()-assist.lastLogin.time<90000 ? assist.lastLogin.token : assist.token,kind:kind,canConfirm:!!(retry && !h5 && id!==1004),view:view,args:a};
  }
  function assistFastPump(){
    if(!assist.redPacketsEnabled || !assist.fastEnabled || assist.locked || assistDialog())return;
    if(typeof PlayerModel==='undefined' || !PlayerModel.inst.role)return;
    var pending=assist.packets.filter(function(p){return p.fast && p.attempts===0 && p.state==='new';});
    if(!pending.length)return;
    var wait=Math.max(0,200-(Date.now()-assist.lastClaim));
    if(wait>0){
      if(!assist.fastTimer){assist.fastTimer=true;setTimeout(function(){assist.fastTimer=false;assistFastPump();},wait);}
      return;
    }
    for(var i=0;i<pending.length;i++){
      var p=pending[i],cfg=ChatModel.inst.GetHongbaoMainCfg(p.type);
      if(p.expires<=Time.GetServerTime()){p.state='expired';continue;}
      if(!cfg || !Array.isArray(cfg.hongbao_channel) || cfg.hongbao_channel.indexOf(p.channel)<0 || !ChatModel.inst.CheckRedPacketCanGrab(p.type,false)){p.state='restricted';continue;}
      var info=ChatModel.inst.GetRedPacketInfoById(p.id);
      if(info){
        var vo=new RedPacketVo(info),state=vo.GetStatus();
        if(String(vo.GetRedPacketId())!==String(p.id) || vo.GetChannelId()!==p.channel || String(vo.GetSessionId())!==String(p.session) || vo.GetHongbaoMainId()!==p.type){p.state='mismatch';continue;}
        if(state===1){p.state='claimed';continue;}
        if(state===2 || state===3){p.state='finished';continue;}
      }
      if(assist.attempted[p.key])continue;
      // The received chat message already supplies the original claim context.
      // Use the normal claim request immediately, then verify the server response.
      var now=Date.now();assist.attempted[p.key]=p.expires;p.attempts=1;p.sent=now;p.state='pending';assist.lastClaim=now;
      ChatModel.inst.GrabRedPacket(p.id,p.channel,p.session,p.type);
      assistFastPump();return;
    }
  }
  function assistPacketRecords(){
    return assist.packets.map(function(p){
      var r={key:p.key,id:String(p.id),channel:p.channel,type:p.type,seenAt:p.seenAt,expires:p.expires,status:p.state,attempted:p.attempts>0,sentAt:p.sent||null,requestDelayMs:p.sent ? Math.max(0,p.sent-p.seenAt) : null};
      try {
        var info=ChatModel.inst.GetRedPacketInfoById(p.id),cfg=ChatModel.inst.GetHongbaoMainCfg(p.type);
        r.name=cfg && cfg.hongbao_show_name ? L(cfg.hongbao_show_name) : '聊天红包';
        r.currencyId=cfg && cfg.huobi_id || null;
        r.currencyName=r.currencyId && typeof ItemHelper!=='undefined' && typeof ItemHelper.GetItemName==='function' ? ItemHelper.GetItemName(r.currencyId) : null;
        if(info && PlayerModel.inst.role){
          var vo=new RedPacketVo(info);
          if(String(vo.GetRedPacketId())===String(p.id) && vo.GetChannelId()===p.channel && String(vo.GetSessionId())===String(p.session) && vo.GetHongbaoMainId()===p.type){
            r.serverStatus=vo.GetStatus();r.totalMoney=vo.GetTotalMoney();r.totalNum=vo.GetTotalNum();r.remainingNum=vo.GetCurRestNum();
            if(r.serverStatus===1)r.myAmount=vo.GetMyGrabMoneyNum();
          }
        }
      }catch(e){}
      return r;
    });
  }
  var popupAttempts={},popupLastAction=0,noKeyBossExits=0,noKeyExitAt=0;
  var popupRecorder={sequence:0,active:{},queue:[],listening:false,dropped:0};
  function popupData(value){
    var seen=[],nodes=0;
    function copy(v,depth,key){
      if(/pass(word)?|token|auth|cookie|secret|sign(ature)?|accountInfo|phone|mobile|email|openid|unionid|user_uid|身份证/i.test(key||''))return '[REDACTED]';
      if(++nodes>150)return '[LIMIT]';
      if(v===null || v===undefined)return null;
      if(typeof v==='string')return v.slice(0,1000);
      if(typeof v==='boolean')return v;
      if(typeof v==='number')return Number.isFinite(v)?v:String(v);
      if(typeof v==='bigint')return String(v);
      if(typeof v==='function')return {functionName:String(v.name||'anonymous').slice(0,120),argumentCount:v.length};
      if(typeof v!=='object')return '['+typeof v+']';
      if(seen.indexOf(v)>=0)return '[CIRCULAR]';
      if(depth>=3)return '[DEPTH_LIMIT]';
      seen.push(v);
      if(Array.isArray(v))return v.slice(0,15).map(function(x){return copy(x,depth+1,'');});
      var out={};Object.keys(v).slice(0,40).forEach(function(k){
        if(/gameObject|owner|parent|world|battleData|_pipeline|agents|sender|avatar|texture|socket|_dataSource/i.test(k)){out[k]='[OMITTED]';return;}
        var d=Object.getOwnPropertyDescriptor(v,k);out[k]=d && Object.prototype.hasOwnProperty.call(d,'value') ? copy(d.value,depth+1,k) : '[ACCESSOR_NOT_READ]';
      });return out;
    }
    return copy(value,0,'');
  }
  function popupRead(v,k){try{return v && v[k];}catch(e){return undefined;}}
  function popupText(value){return typeof value==='string' ? value.slice(0,1000) : '';}
  function popupComponent(id,v){
    if(!v || !v.gameObject || !v.gameObject.visible || v.gameObject.destroyed)return null;
    var cfg=v.viewVo||{},name=String(cfg.name||v.viewName||'View_'+id),type=cfg.type;
    // Game UI types 1/4/5 are popups; include known dialog names even with missing config.
    if(cfg.mask!==2 && [1,4,5].indexOf(type)<0 && !/Notify|Tips|Result|Confirm|Sure|Invitation|Invivation|Reborn|PopView/i.test(name) && [1004,1137,1183].indexOf(Number(id))<0)return null;
    // Chat content and text-entry pages are not popup diagnostics.
    if(/ChatView|ChatMain|PrivateChat|InputView|LoginView|Rename|EditView/i.test(name))return null;
    var texts={},buttons=[],callbacks={},args=popupRead(v,'args');
    Object.keys(v).slice(0,250).forEach(function(k){
      var desc=Object.getOwnPropertyDescriptor(v,k);if(!desc || !Object.prototype.hasOwnProperty.call(desc,'value'))return;
      var c=desc.value;
      if(c && typeof c==='object' && /Btn$|Button$/.test(k)){
        buttons.push({field:k,label:popupText(popupRead(c,'label')||popupRead(c,'text')),visible:popupRead(c,'visible')!==false,disabled:popupRead(c,'disabled')===true || popupRead(c,'mouseEnabled')===false});
      }else if(/title|content|wenben|biaoti|desc|message|tip|Txt$|Lbl$|Label$/i.test(k) && !/input|password|account|phone/i.test(k)){
        var text=popupText(typeof c==='string' ? c : popupRead(c,'text'));
        if(text && texts[k]===undefined && Object.keys(texts).length<25)texts[k]=text;
      }
    });
    if(args && typeof args==='object')Object.keys(args).forEach(function(k){var d=Object.getOwnPropertyDescriptor(args,k);if(d && typeof d.value==='function')callbacks[k]={name:String(d.value.name||'anonymous'),argumentCount:d.value.length};});
    var scene={};
    try{scene.sceneType=SceneMgr.inst.GetCurSceneType();scene.areaId=WildIdleModel.inst.GetCurAreaId();scene.fieldId=WildIdleModel.inst.GetCurFieldId();}catch(e){}
    var title=popupText(popupRead(args,'title'))||texts.biaotiTxt||texts.titleTxt||name;
    var body=popupText(popupRead(args,'content'))||texts.wenben1Lbl||texts.descTxt||'';
    return {viewId:Number(id),viewName:name,title:title,body:body,data:{schemaVersion:1,viewType:type||null,mask:cfg.mask||null,blankClose:!!commonBackgroundClose(v) || (cfg.mask===2 && typeof BaseView!=='undefined' && BaseView.prototype && v.OnMaskBgClick===BaseView.prototype.OnMaskBgClick),scene:scene,visible:true,texts:texts,buttons:buttons.slice(0,25),callbacks:callbacks,
      parameters:popupData({args:args,openInfo:popupRead(v,'openInfo'),params:popupRead(v,'params'),openParameters:popupRead(v,'_params')}),collection:'read-only; no callbacks executed; secrets and object graphs omitted'},args:args,params:popupRead(v,'_params'),view:v};
  }
  function popupQueue(record){
    if(popupRecorder.queue.length>=200){popupRecorder.queue.shift();popupRecorder.dropped++;}
    popupRecorder.queue.push(record);
  }
  function popupSnapshot(id,forceOpen){
    try {
      var v=UIMgr.inst.GetView(id),info=popupComponent(id,v);if(!info)return;
      var previous=popupRecorder.active[id],fresh=forceOpen || !previous || previous.view!==v || previous.args!==info.args || previous.params!==info.params;
      var content=JSON.stringify({title:info.title,body:info.body,data:info.data}).replace(/\(\d+\)/g,'(#)');
      if(!fresh && previous.content===content)return;
      if(!fresh && previous.updates>=5)return;
      var occurrence=fresh ? assist.session+':popup:'+(++popupRecorder.sequence) : previous.occurrence;
      var phase=fresh ? 'opened' : 'updated',now=Date.now();
      popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:occurrence,phase:phase,capturedAt:now,viewId:info.viewId,viewName:info.viewName,title:info.title,body:info.body,data:info.data});
      popupRecorder.active[id]={view:v,args:info.args,params:info.params,occurrence:occurrence,openedAt:fresh ? now : previous.openedAt,content:content,updates:fresh ? 0 : previous.updates+1,info:info};
    }catch(e){}
  }
  function popupClosed(id){
    var previous=popupRecorder.active[id];if(!previous)return;
    popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:previous.occurrence,phase:'closed',capturedAt:Date.now(),viewId:Number(id),viewName:previous.info.viewName,title:previous.info.title,body:previous.info.body,data:{visible:false,reason:'close observed; actual user/automatic action not inferred'}});
    delete popupRecorder.active[id];
  }
  function popupObserve(){
    try {
      if(typeof UIMgr==='undefined' || !UIMgr.inst || typeof UIMgr.inst.GetView!=='function')return;
      if(!popupRecorder.rewardListening && typeof AreaBossEvent!=='undefined' && typeof EventMgr!=='undefined'){
        EventMgr.AddEvent(AreaBossEvent.Open_Reward_Box,popupRecorder,function(reward){
          var p=popupRecorder.active[1276];if(!p || !popupAttempts[p.occurrence])return;
          popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:p.occurrence,phase:'rewarded',capturedAt:Date.now(),viewId:1276,viewName:'AreaBossResultView',title:p.info.title,body:'服务器已返回区域BOSS宝箱奖励',data:{rule:'areaBossBox',serverConfirmed:true,rewards:popupData(reward),keysAfter:AreaBossModel.inst.GetTodayRewardTimes()}});
        });popupRecorder.rewardListening=true;
      }
      if(!popupRecorder.listening && typeof GameCoreEvent!=='undefined' && typeof EventMgr!=='undefined'){
        EventMgr.AddEvent(GameCoreEvent.OpenView,popupRecorder,function(id){popupSnapshot(id,true);});
        EventMgr.AddEvent(GameCoreEvent.CloseView,popupRecorder,popupClosed);
        popupRecorder.listening=true;
      }
      var map=UIMgr.inst._openViews,visible={};
      if(map && map.forEach)map.forEach(function(view,id){if(view && view.gameObject && view.gameObject.visible && !view.gameObject.destroyed){visible[id]=true;popupSnapshot(id,false);}});
      [1004,1137,1183,1023,1017,1276].forEach(function(id){var v=UIMgr.inst.GetView(id);if(v && v.gameObject && v.gameObject.visible){visible[id]=true;popupSnapshot(id,false);}});
      Object.keys(popupRecorder.active).forEach(function(id){if(!visible[id])popupClosed(id);});
    }catch(e){}
  }
  function popupBatch(ack){
    if(typeof ack==='number')popupRecorder.queue=popupRecorder.queue.filter(function(e){return Number(e.eventId.split(':').pop())>ack;});
    return popupRecorder.queue.slice(0,5);
  }

  function assistStatus(){
    popupObserve();
    assistListen();assistScan();
    var d=assistDialog();
    return {version:1,noKeyBossExits:noKeyBossExits,popupHandlingVersion:2,areaBossVersion:2,popupSession:assist.session,popupDropped:popupRecorder.dropped,popupEvents:popupBatch(),packets:assistPacketRecords(),session:assist.session,confirmations:assist.confirmations,replacedEvents:assist.replacedEvents,locked:assist.locked,claimed:assist.claimed,queued:assist.packets.filter(function(p){return ['new','pending'].indexOf(p.state)>=0;}).length,
      dialog:d ? {id:d.id,token:d.token,kind:d.kind,canConfirm:d.canConfirm} : null};
  }
  function assistPacket(){
    if(typeof ChatModel==='undefined' || typeof RedPacketVo==='undefined' || typeof PlayerModel==='undefined' || !PlayerModel.inst.role)return;
    var now=Date.now();if(!assist.fastEnabled && now-assist.lastAction<3000)return;
    for(var i=0;i<assist.packets.length;i++){
      var p=assist.packets[i];if(['new','pending'].indexOf(p.state)<0)continue;
      if(p.expires<=Time.GetServerTime()){p.state='expired';continue;}
      var info=ChatModel.inst.GetRedPacketInfoById(p.id);
      if(info){
        var vo=new RedPacketVo(info),state=vo.GetStatus();
        // The server context must match the original received message.
        if(String(vo.GetRedPacketId())!==String(p.id) || vo.GetChannelId()!==p.channel || String(vo.GetSessionId())!==String(p.session) || vo.GetHongbaoMainId()!==p.type){p.state='mismatch';continue;}
        if(state===1){if(p.attempts>0)assist.claimed++;p.state='claimed';continue;}
        if(state===2 || state===3){p.state='finished';continue;}
        var cfg=ChatModel.inst.GetHongbaoMainCfg(p.type);
        if(!cfg || !Array.isArray(cfg.hongbao_channel) || cfg.hongbao_channel.indexOf(p.channel)<0 || !ChatModel.inst.CheckRedPacketCanGrab(p.type,false)){p.state='restricted';continue;}
        // Never resubmit an uncertain grant; query until acknowledged or expired.
        if(state===0 && p.attempts===0 && !assist.attempted[p.key]){
          assist.attempted[p.key]=p.expires;p.attempts=1;p.sent=now;p.state='pending';assist.lastAction=now;
          ChatModel.inst.GrabRedPacket(p.id,p.channel,p.session,p.type);return;
        }
      }
      if(now-p.checked>=10000){p.checked=now;assist.lastAction=now;ChatModel.inst.RequestRedPacketInfo(p.id);return;}
    }
  }
  function handleKnownPopup(m){
    if(assistDialog() || Date.now()-popupLastAction<3000)return;
    popupObserve();
    var ids=[1023];
    for(var i=0;i<ids.length;i++){
      var id=ids[i],enabled=id===1023 ? m.idleReward===true : m.rewardNotice===true;
      if(!enabled)continue;
      var v=UIMgr.inst.GetView(id),p=popupRecorder.active[id];
      if(!v || !p || p.view!==v || !v.gameObject || !v.gameObject.visible || v.gameObject.destroyed || Date.now()-p.openedAt<2000 || popupAttempts[p.occurrence])continue;
      var name=v.viewVo && v.viewVo.name;
      if(name!==(id===1023 ? 'WildIdleRewardView' : 'NotifyItemGainView'))continue;
      var action;
      if(id===1023){
        var btn=v.rewardReceiveBtn;
        if(!btn || btn.visible===false || btn.disabled===true || btn.mouseEnabled===false || typeof v.OnrewardReceiveBtnClick!=='function')continue;
        if(typeof WildIdleModel==='undefined' || !WildIdleModel.inst || !Array.isArray(WildIdleModel.inst.incomeInfo) || WildIdleModel.inst.incomeInfo.length===0)continue;
        action='OnrewardReceiveBtnClick';
      }else{
        if(!Array.isArray(v.gainItems) || !v.gainItems.length || typeof v.Close!=='function')continue;
        action='Close';
      }
      // One attempt per visible occurrence; never repeatedly claim on uncertain acknowledgement.
      popupAttempts[p.occurrence]=true;popupLastAction=Date.now();
      var result='已触发原有处理，等待游戏确认';
      try{v[action]();}catch(e){result='处理失败，保留弹窗等待人工检查';}
      popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:p.occurrence,phase:'handled',capturedAt:Date.now(),viewId:id,viewName:p.info.viewName,title:p.info.title,body:p.info.body,data:{action:action,result:result,rule:id===1023 ? 'idleReward' : 'rewardNotice',confirmation:'Only a later close event confirms dismissal; no award amount inferred'}});
      return;
    }
  }
  function commonBackgroundClose(v){
    var sub=v && v.commonBg1SubView,btn=sub && sub.closeBtn,label=sub && sub.guanbiTxt;
    if(typeof CommonBg1SubView==='undefined' || !sub || sub.baseView!==v || sub.OncloseBtnClick!==CommonBg1SubView.prototype.OncloseBtnClick)return null;
    if(!btn || btn.visible===false || btn.disabled===true || btn.mouseEnabled===false || (sub.gameObject && sub.gameObject.visible===false))return null;
    var text=label && label.text;
    if(text!==L('com_close_windows') && text!=='点击空白处关闭')return null;
    return sub;
  }
  function handleBlankPopup(m){
    if(m.blankClose!==true || assist.locked || assistDialog() || Date.now()-popupLastAction<3000)return;
    var adapt=typeof UIAdaptMgr!=='undefined' && UIAdaptMgr.inst,v=adapt && adapt.maskView,sub=null,action='UIAdaptMgr._OnMaskClick';
    var candidates=[],map=UIMgr.inst._openViews;
    function add(view){if(view && view.gameObject && view.gameObject.visible && !view.gameObject.destroyed && commonBackgroundClose(view) && candidates.indexOf(view)<0)candidates.push(view);}
    if(map && map.forEach)map.forEach(add);add(UIMgr.inst.GetView(1017));add(UIMgr.inst.GetView(1276));
    if(candidates.length===1){
      var c=candidates[0];
      if(!v || v===c || !v.gameObject || !v.gameObject.visible || (Number.isFinite(c.layerOrder) && Number.isFinite(v.layerOrder) && c.layerOrder>v.layerOrder) || (c.gameObject.parent && c.gameObject.parent===v.gameObject.parent && c.gameObject.parent.getChildIndex(c.gameObject)>c.gameObject.parent.getChildIndex(v.gameObject))){v=c;sub=commonBackgroundClose(c);action='CommonBg1SubView.OncloseBtnClick';}
    }
    var cfg=v && v.viewVo;
    if(!cfg || cfg.id===1023 || (cfg.id===1276 && v.open!==true) || !v.gameObject || !v.gameObject.visible || v.gameObject.destroyed || UIMgr.inst.GetView(cfg.id)!==v)return;
    if(!sub){
      if(cfg.mask!==2 || !adapt || !adapt.closeTipsGo || adapt.closeTipsGo.visible!==true || typeof adapt._OnMaskClick!=='function' || typeof BaseView==='undefined' || typeof BaseView.prototype.OnMaskBgClick!=='function' || v.OnMaskBgClick!==BaseView.prototype.OnMaskBgClick)return;
    }
    popupSnapshot(cfg.id,false);var p=popupRecorder.active[cfg.id],attempt=p && p.occurrence+':blank';
    if(!p || p.view!==v || Date.now()-p.openedAt<2000 || popupAttempts[attempt])return;
    popupAttempts[attempt]=true;popupLastAction=Date.now();var result='已触发游戏空白关闭，等待关闭事件';
    try{if(sub)sub.OncloseBtnClick();else adapt._OnMaskClick();}catch(e){result='空白关闭失败，等待人工检查';}
    popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:p.occurrence,phase:'handled',capturedAt:Date.now(),viewId:Number(cfg.id),viewName:p.info.viewName,title:p.info.title,body:p.info.body,data:{action:action,rule:'blankClose',result:result,mask:cfg.mask||null,confirmation:'Dismissal confirmed only by a later close event'}});
  }
  function handleAreaBossBox(m){
    if(m.areaBossBox!==true || assist.locked || assistDialog() || Date.now()-popupLastAction<3000)return;
    var v=UIMgr.inst.GetView(1276),cfg=v && v.viewVo,d=v && v.data;
    if(!v || !cfg || cfg.name!=='AreaBossResultView' || !d || v.open!==false || !v.gameObject || !v.gameObject.visible || v.gameObject.destroyed)return;
    var owned=targetedAreaBosses[d.ins_id+':'+d.mon_point];
    if(!owned || owned.areaId!==m.huntArea || Date.now()<owned.at || Date.now()-owned.at>600000)return;
    try{requireHuntScene(m.huntArea);}catch(e){return;}
    popupSnapshot(1276,false);var p=popupRecorder.active[1276];
    if(!p || popupAttempts[p.occurrence] || Date.now()-p.openedAt<2000)return;
    var keyCount=AreaBossModel.inst.GetTodayRewardTimes();
    if(!(keyCount>0))return; // Never use substitute item 3361 or open a purchase page.
    var free=AreaBossModel.inst.GetAreaBossIsNotRewarded(d.ins_id,d.mon_point);
    var btn=free ? v.specialBtn : v.normalBtn,action=free ? 'OnspecialBtnClick' : 'OnnormalBtnClick';
    if(!btn || btn.visible===false || btn.disabled===true || btn.gray===true || typeof v[action]!=='function')return;
    popupAttempts[p.occurrence]=true;popupLastAction=Date.now();var result='已通过原有按钮请求开箱，等待服务器确认';
    try{v[action]();}catch(e){result='开箱请求失败，等待人工检查';}
    popupQueue({eventId:assist.session+':popup-event:'+(++popupRecorder.sequence),occurrenceId:p.occurrence,phase:'handled',capturedAt:Date.now(),viewId:1276,viewName:cfg.name,title:p.info.title,body:p.info.body,data:{action:action,rule:'areaBossBox',result:result,keyBefore:keyCount,keyItemId:AreaBossModel.inst.boxKeyItemId,insId:d.ins_id,pointId:d.mon_point,free:free,confirmation:'Request only; award must be confirmed by server Open_Reward_Box event'}});
  }
  function avoidEmptyKeyBoss(m){
    if(m.avoidNoKeyBoss!==true || assist.locked || Date.now()-noKeyExitAt<15000)return;
    if(typeof AreaBossModel==='undefined' || typeof AreaBossMgr==='undefined' || !(AreaBossModel.inst.GetTodayRewardTimes()===0) || !AreaBossMgr.inst.GetIsInAreaBossArea())return;
    try{requireHuntScene(m.huntArea);}catch(e){return;}
    if(navigation && navigation.phase==='leavingNoKey')return;
    // Leave only the regional-boss combat zone. Normal-boss patrol intent is retained.
    suspendHunt();changeOwnedAuto(false);noKeyExitAt=Date.now();
    if(!MapModel.inst.CheckIsCanTransfer())return;
    var rows=MapModel.inst.GetMonsterItemDataListByAreaId(m.huntArea,false,false,true),destination=null;
    for(var i=0;i<rows.length;i++){
      if(rows[i].monsterType===3)continue;
      var pos=new Laya.Vector3();WildMapMgr.inst.GetMapPointByTypeAndId1(rows[i].mapId,'wild_mon',rows[i].pointId,pos);pos.scale(.01,pos);
      var tp=MapTool.GetCommonTpPos(pos.clone());if(tp){destination=tp;break;}
    }
    if(!destination)return; // Keep battle off if no safe ordinary-field destination exists.
    var route={areaId:m.huntArea,bossId:0,insId:0,pointId:0,phase:'leavingNoKey'};navigation=route;
    WildIdleModel.inst.HandleWildTPInfo(destination,1,function(){
      if(navigation!==route)return;
      navigation=null;noKeyBossExits++;
    });
  }
  function assistRun(m){
    popupBatch(m.popupAck);
    assist.redPacketsEnabled=m.redPackets===true;assist.fastEnabled=assist.redPacketsEnabled && m.fastRedPackets===true;
    assist.locked=m.locked===true;
    if(assist.locked){
      // Protection owns only assistant navigation/auto mode, never the team's combat state.
      if(navigation || priorAuto!==null){try{var loc=locationSnapshot();suspendHunt();if(loc.kind==='wild')changeOwnedAuto(false);}catch(e){}}
      return assistStatus();
    }
    var d=assistDialog();
    if(m.confirmToken && d && d.token===m.confirmToken && d.canConfirm && d.kind!=='unknown' && assist.confirmedToken!==d.token && Date.now()-(assist.lastConfirm||0)>=10000){
      assist.confirmedToken=d.token;assist.lastConfirm=Date.now();
      // Execute the view's normal handler, including close/callback bookkeeping.
      if(d.id===1137)d.view.OnrightBtnClick();
      else if(d.view.left1Btn && d.view.left1Btn.visible)d.view.Onleft1BtnClick();
      else d.view.OnrightBtnClick();
      assist.confirmations++;
    }
    avoidEmptyKeyBoss(m);
    handleAreaBossBox(m);
    handleKnownPopup(m);
    handleBlankPopup(m);
    if(m.redPackets===true && !assistDialog()){assistFastPump();assistPacket();}
    return assistStatus();
  }

  // Nearby monster selection uses the same distance gate and handler as a normal click.
  var targeting={enabled:false,autoHighest:false,world:null,scope:0,owned:null,lastSwitch:0,locked:false};
  function targetContext(){
    var scene=SceneMgr.inst.GetCurSceneType(),battle=CombatMgr.inst.GetBattleBySceneType(scene);
    var data=battle && battle.battleData,world=data && data.world;
    if(world!==targeting.world){targeting.world=world;targeting.scope++;targeting.owned=null;targeting.lastSwitch=0;}
    if(!targeting.enabled || !world || !battle._fighting || CombatMgr.inst.GetCurRenderSceneType()!==scene || !data.CheckCurHeroCreated() || CombatTPMgr.inst.GetIsTPing())return null;
    var monitor=world.GetGlobalComp(CompEnum.GMonitor),eid=monitor && monitor.GetHeroEid(world.localAgentId),hero=eid && world.GetEntity(eid);
    if(!hero || UtilsInterface.EntityUtils.CheckEntityHasDieTypeTag(hero))return null;
    var transform=hero.Get(RCompEnum.RTransform),controller=world.GetGlobalComp(RCompEnum.GController);
    var radius=ConfigMgr.inst.GetBattleParam('lock_distance')/100;
    if(!transform || !controller || !Number.isFinite(radius) || radius<=0)return null;
    return {scene:scene,world:world,hero:hero,pos:transform.pos,controller:controller,radius:radius};
  }
  function targetRows(ctx){
    var entities=ctx.world.dataCenter && ctx.world.dataCenter.entities,rows=[];
    if(!entities)return rows;
    var ai=Utils.GetPlayerControlHeroAIComp(ctx.hero),selected=ai && ai.playerSelectedTargetEid;
    Object.keys(entities).forEach(function(k){
      var entity=entities[k];
      if(!entity || [3,6].indexOf(entity.type)<0 || ctx.world.GetEntity(entity.eid)!==entity || UtilsInterface.EntityUtils.CheckEntityHasDieTypeTag(entity))return;
      if(Utils.GetRelationshipWithoutCombat(ctx.hero,entity)!==CType.Relationship.Enemy)return;
      var transform=entity.Get(RCompEnum.RTransform),attr=entity.Get(CompEnum.Attr);
      if(!transform || !attr)return;
      var distance=Utils.CalcDistance(ctx.pos,transform.pos),hp=attr.GetNowHp(true),maxHp=attr.GetMaxHp();
      if(!Number.isFinite(distance) || distance>ctx.radius || !Number.isFinite(hp) || !Number.isFinite(maxHp) || hp<=0 || maxHp<=0)return;
      var cfg=ConfigMgr.inst.GetKey(configTable.monster_type,entity.cfgId,false);
      rows.push({eid:String(entity.eid),name:cfg ? L(cfg.name) : '怪物',cfgId:entity.cfgId,hp:hp,maxHp:maxHp,distance:distance,
        selected:String(selected)===String(entity.eid),requested:String(ctx.controller.curHeroSelectTargetEid)===String(entity.eid)});
    });
    rows.sort(function(a,b){return b.hp-a.hp || a.distance-b.distance || a.eid.localeCompare(b.eid);});
    return rows;
  }
  function targetRelease(){
    var world=targeting.world,controller=world && world.GetGlobalComp(RCompEnum.GController);
    if(controller && targeting.owned!==null && String(controller.curHeroSelectTargetEid)===String(targeting.owned))ClientStateSyncUtils.ResetLocalHeroAISelectTargetEid(world);
    targeting.owned=null;
  }
  function targetChoose(ctx,eid){
    if(assist.locked || targeting.locked)throw Error('账号保护已暂停集火操作');
    var row=targetRows(ctx).find(function(r){return r.eid===String(eid);});
    if(!row)throw Error('目标已死亡、离开范围或无法选中');
    var entity=ctx.world.GetEntity(Number(row.eid));
    if(!entity || String(entity.eid)!==row.eid)throw Error('目标已经变化');
    EntityClickHelper.OnClickMonster(ctx.hero,entity);
    if(String(ctx.controller.curHeroSelectTargetEid)!==row.eid)throw Error('游戏未接受目标选择');
    targeting.owned=row.eid;targeting.lastSwitch=Date.now();return row;
  }
  function targetStatus(tick){
    var ctx=targetContext(),rows=ctx ? targetRows(ctx) : [];
    if(tick && ctx && targeting.autoHighest && !assist.locked && !targeting.locked){
      var candidates=rows.filter(function(r){return r.name.indexOf('图腾')<0;});
      var excluded=rows.find(function(r){return r.requested && r.name.indexOf('图腾')>=0;});
      if(excluded && excluded.eid===targeting.owned)targetRelease();
      var top=candidates[0],current=candidates.find(function(r){return r.requested;});
      if(top && current && current.hp===top.hp)top=current;
      if(top && !top.requested && Date.now()-targeting.lastSwitch>=800)targetChoose(ctx,top.eid);
      rows=targetRows(ctx);
    }
    return {version:1,enabled:targeting.enabled,autoHighest:targeting.autoHighest,scope:String(targeting.scope),sceneType:ctx ? ctx.scene : null,
      ready:!!ctx,locked:assist.locked || targeting.locked,radius:ctx ? ctx.radius : null,rows:rows};
  }
  function targetDispatch(m){
    if(m.op==='targetMode'){
      targeting.locked=m.locked===true;
      if(m.enabled!==true){targetRelease();targeting.enabled=false;targeting.autoHighest=false;return targetStatus(false);}
      targeting.enabled=true;targeting.autoHighest=m.autoHighest===true;
      return targetStatus(true);
    }
    if(m.op==='targetTick'){targeting.locked=m.locked===true;return targetStatus(true);}
    if(m.op==='targetSelect'){
      var ctx=targetContext();
      if(!ctx || String(m.scope)!==String(targeting.scope))throw Error('场景已变化，请等待列表刷新');
      targetChoose(ctx,m.eid);targeting.autoHighest=false;return targetStatus(false);
    }
  }

  function dispatch(m) {
    if(['targetMode','targetTick','targetSelect'].indexOf(m.op)>=0)return targetDispatch(m);
    if(m.op==='assistStatus')return assistStatus();
    if(m.op==='assistRun')return assistRun(m);
    if(m.op==='keyboardMode') {
      escapeHeld=false;
      if(m.enabled===true)installKeyboard();
      clearArrowKeys();keyboard.enabled=m.enabled===true;
      if(keyboard.enabled && m.preserveNavigation!==true){navigation=null;EventFollowMgr.inst.ClearEventFollow();}
      return keyboardStatus();
    }
    if(m.op==='keyboardKeys') {
      if(!keyboard.enabled)throw Error('keyboard_disabled');
      var escapeDown=Array.isArray(m.keys) && m.keys.indexOf(27)>=0;
      if(escapeDown && !escapeHeld){escapeHeld=true;keyboard.lastEscape=escapeBack();keyboard.lastEscape.at=Date.now();}else escapeHeld=escapeDown;
      clearArrowKeys();keyboard.lastNativeAt=Date.now();
      if(!typingText())(Array.isArray(m.keys)?m.keys:[]).forEach(function(code){if([37,38,39,40].indexOf(code)>=0)keyboard.pressed[code]=true;});
      keyboard.eventCount++;keyboard.lastEvent={keys:Object.keys(keyboard.pressed).map(Number),time:Date.now(),source:'native'};
      return keyboardStatus();
    }
    if (m.op === 'list') return snapshot();
    if (m.op === 'location') return locationSnapshot();
    if (m.op === 'suspendHunt') return suspendHunt();
    if (m.op === 'attackMode') {
      requireHuntScene(m.areaId);
      var bd=CombatMgr.inst.GetHightestPriorityBattle();
      if(!bd) throw Error('game_not_ready');
      priorAuto=bd.battleData.IsHeroAutoUseSkill();
      changeOwnedAuto(true);
      return {previousAuto:priorAuto};
    }
    if (m.op === 'refresh') {
      if(!WildIdleModel.inst.GetCurAreaId())throw Error('game_not_ready');
      MapModel.inst.RequestBossReviveInfo(WildIdleModel.inst.GetCurAreaId());
      if(typeof AreaBossControl!=='undefined')AreaBossControl.inst.area_boss_boss_info_c2s({});
      return {requested:true};
    }
    if (m.op === 'goto') {
      requireHuntScene(m.areaId);
      var rows = snapshot().rows;
      var b = rows.find(function (b) { return b.bossId === m.bossId && b.insId === m.insId && b.pointId === m.pointId; });
      if (!b || b.status !== 'ready') throw Error('target_not_confirmed_ready');
      if(b.kind==='areaBoss' && !(b.keyCount>0))throw Error('area_boss_no_key');
      if (WildModel.inst.CheckIsWildSync() && !WildModel.inst.IsWildSyncLeader()) throw Error('not_team_leader');
      if (CombatTPMgr.inst.GetIsTPing()) throw Error('teleport_in_progress');
      if (!MapModel.inst.CheckIsCanTransfer()) throw Error('cannot_transfer');
      var pos = new Laya.Vector3();
      WildMapMgr.inst.GetMapPointByTypeAndId1(b.mapId, 'wild_mon', b.pointId, pos);
      pos.scale(.01, pos);
      var params={pos:pos, iconPath:MapBossIcon[b.kind==='areaBoss' ? 3 : 2], isReachEnd:true, followType:2, uid:b.uid, isAutoGoTo:true};
      var tp=MapTool.GetCommonTpPos(pos.clone());
      if(!tp) throw Error('no_teleport_destination');
      clearOwnedPath();
      navigation={areaId:WildIdleModel.inst.GetCurAreaId(),bossId:b.bossId,insId:b.insId,pointId:b.pointId,phase:'teleport',target:{x:pos.x,y:pos.y,z:pos.z}};
      if(b.kind==='areaBoss')targetedAreaBosses[b.insId+':'+b.pointId]={areaId:WildIdleModel.inst.GetCurAreaId(),at:Date.now()};
      var route=navigation;
      WildIdleModel.inst.HandleWildTPInfo(tp,1,function(){
        if(navigation!==route) return;
        try{requireHuntScene(route.areaId);}catch(e){suspendHunt();return;}
        params.pos=pos;
        beginBossRoute(route,params);
      });
      return {requested:true,target:b};
    }
    if (m.op === 'stop') {
      targetedAreaBosses={};
      var inWild=locationSnapshot().kind==='wild';
      suspendHunt();if(inWild)changeOwnedAuto(false);
      return {stopped:true};
    }
    throw Error('unsupported_operation');
  }
  function connect() {
    if (stopped) return;
    try {
      socket = new WebSocket('__CODEX_WS_URL__');
      socket.onopen=function(){socket.send(JSON.stringify({hello:'yzlm-native-boss-v2',token:'__CODEX_TOKEN__'}));};
      socket.onmessage=function(e){
        var m;
        try { m=JSON.parse(e.data); var result=dispatch(m); socket.send(JSON.stringify({id:m.id,result:result})); }
        catch(err){if(socket.readyState===1)socket.send(JSON.stringify({id:m&&m.id,error:String(err&&err.message||err)}));}
      };
      socket.onclose=function(){
        try{targetRelease();}catch(e){}targeting.enabled=false;targeting.autoHighest=false;
        assist.redPacketsEnabled=false;assist.fastEnabled=false;
        keyboard.enabled=false;clearArrowKeys();
        if(priorAuto!==null){try{var inWild=locationSnapshot().kind==='wild';suspendHunt();if(inWild)changeOwnedAuto(false);}catch(e){}priorAuto=null;}
        if(!stopped)setTimeout(connect,3000);
      };
      socket.onerror=function(){};
    } catch(e) { setTimeout(connect,3000); }
  }
  setTimeout(connect,1000);
  return true;
})()
