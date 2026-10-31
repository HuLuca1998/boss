# 本机探索 API（1.4.8）

首领助手运行并连接新注入的游戏脚本后，可通过本机 WebSocket 获取地图与界面，逐步执行探索。无任意脚本执行入口，不直接构造游戏服务端协议。

## 连接

凭据从 `~/Library/Application Support/HeroBossAssistant/Connection.json` 读取，权限为 0600。不要上传此文件或把令牌写进日志。连接 `ws://127.0.0.1:<port>`，首条消息为 `{"hello":"yzlm-controller-v1","token":"本机令牌"}`。服务返回版本和游戏连接状态；控制器不会替换游戏连接。

请求 `{"id":1,"op":"exploreMap"}`，响应 `{"id":1,"result":{...}}` 或 `{"id":1,"error":"..."}`。响应按 id 对应；错误、超时不代表动作未发生，先刷新状态再决定是否重试。

仓库自带 Node 22+ 客户端：

```sh
node scripts/game-api.mjs exploreMap '{"areaId":7,"includeFog":true}'
node scripts/game-api.mjs exploreUI
node scripts/game-api.mjs exploreState
node scripts/game-api.mjs exploreRender '{}' /tmp/game-render.jpg
node scripts/game-api.mjs exploreFollow '{"eventId":123}'
node scripts/game-api.mjs exploreMove '{"x":12.5,"z":34.2}'
node scripts/game-api.mjs exploreClick '{"revision":1,"nodeId":"123"}'
node scripts/game-api.mjs exploreStop
```

## 接口

| op | 参数与结果 |
| --- | --- |
| exploreMap | 可选 areaId（默认当前区域）、includeFog。返回所有区域概览、选定区域的各子地图和事件、分类完成计数、场景位置、当前跟随事件。字段和地图数据来自游戏配置，状态来自游戏已接收数据 |
| exploreState | 只读场景、角色血量/死亡/自动战斗、范围内敌人血量与位置、独立实体ID、实际选中状态、单事件寻路和跟随目标；不启用集火、不选怪。nearbyReady=false 时空列表不代表周围没有怪 |
| exploreUI | 返回可见2D节点树、窗口ID列表、文字、全局位置、尺寸、点击监听标记、revision。过滤3D场景树；可传 viewId 只读取某个实际可见窗口。上限1500节点、24层，截断会标记truncated；截断时应按窗口继续读取 |
| exploreRender | 使用游戏引擎原生 Conch 截图方法，返回 JPEG dataURL 和尺寸。限制 500 万像素及约 850KB；不支持或过大时报错，不伪造图像。视引擎渲染能力可能只包含 UI，须与实际画面核对 |
| exploreClick | revision + nodeId，普通节点执行原生 CLICK；KButton 执行原生按下/松开事件，保留其单击和冷却逻辑。编号只在最近一次界面快照后 10 秒内有效；节点隐藏、销毁、禁用或已点击则拒绝。它不是屏幕坐标点击，不保证每个控件都有 CLICK 处理器 |
| exploreFollow | eventId，调用原生单事件自动寻路。仅接受采集、宝箱、传送石、怪群、污染类名称；拒绝方尖碑、聚魂类、神像、已完成事件及未解锁子地图 |
| exploreMove | x、z（游戏世界坐标），通过原生路径检查后寻路；保留游戏自身场景、悬赏、队伍和路径限制 |
| exploreStop | 停止单事件、整图及隐藏事件自动寻路，取消跟随并关闭野外自动战斗 |
| location / list | 原有场景位置 / 当前首领快照 |

`requested: true` 仅表示调用已交给游戏；`completed: false` 不表示失败。每步必须再次读取地图状态或界面，确认完成。没有后台全图自动执行循环，调用方负责逐步规划、观察和停止。

事件 `observed: false`、`status: null` 表示没有该事件实时数据，不能认定未完成；`done` 根据游戏完成状态判定。子地图 fog 仅返回已经观测的数据；未知区域不会假装已揭开。includeFog 提供原始 fog words、division、blockSize、地图 origin，可供规划器分析，不调用修改迷雾的方法。子地图 progress 根据已观测普通计数事件的完成权重计算；数据不全时为 null，与迷雾覆盖率不同。1.4.5 的子地图 progress 可能误报 0，改用分类计数核验。

## 运行约束

- 变更操作在助手维护或账号保护期间拒绝；使用前须停止自动首领攻略并关闭附近集火，避免抢占控制。
- 只监听本机回环地址，沿用受本机文件权限保护的连接令牌；控制器不能使用任意内部指令或回填游戏响应。
- 点击接口是通用原生 UI 工具，调用方须核对节点文字、父节点和截图。探索任务不操作方尖碑、聚魂匣，不购买、不分享、不消耗付费资源，也不领取未知确认框。
- 读取的地图配置可能包含尚未开放内容，以 unlocked 和实际场景为准。到开放时间后重新读取；游戏版本改变或路径受阻时先重新核验。
- 1.4.5 需要重新注入。1.4.7 同样需要重新注入。更新安装与注入分开执行，注入会重启游戏一次。

## 探索调用流程

1. 用 exploreState 与 location 检查实际场景、存活状态、寻路和账号保护；用 exploreMap 选择 unlocked 的子地图和允许事件。地图返回的是游戏已接收状态，不是一次新的服务器查询。
2. 灰色区域规划读取 includeFog；每个 word 包含 bitsPerWord 位，子格 index=row*division+col，位为 words[floor(index/bitsPerWord)] 的 index%bitsPerWord 位。格子中心世界坐标为 x=origin.x-(col+0.5)*blockSize、z=origin.z+(row+0.5)*blockSize；仍须经过游戏寻路检查，矩形迷雾也覆盖不可行走区，不能追求整个数组全亮。
3. 用 exploreMove 或 exploreFollow 发起一步；多次读取位置与 navigation 对比真实位移、目标距离、是否仍在寻路，停滞则重新检查界面，不无限重发。
4. 用最新 exploreUI 查找按钮及父节点，配合截图确认后点击；点击后重新读取界面/事件状态。遇到条件面板，以界面说明和 conditions 原生前置串共同核验，不绕过限制。
5. 用 exploreState 判断真实敌人血量变化及死亡；用 exploreMap 的 done/分类计数确认事件和宝箱完成。仅发出动作不能计入完成。
6. 停止时 exploreStop，重新读取状态确认路径退出、自动战斗关闭。

原生前置条件串是规则标识，不能仅从数字推断可操作；优先使用游戏展示的文字。截图接口只含 UI 的场景需用窗口截图补足 3D 画面。
