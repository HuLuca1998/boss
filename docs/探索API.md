# 本机探索 API（1.4.6）

首领助手运行并连接新注入的游戏脚本后，可通过本机 WebSocket 获取地图与界面，逐步执行探索。无任意脚本执行入口，不直接构造游戏服务端协议。

## 连接

凭据从 `~/Library/Application Support/HeroBossAssistant/Connection.json` 读取，权限为 0600。不要上传此文件或把令牌写进日志。连接 `ws://127.0.0.1:<port>`，首条消息为 `{"hello":"yzlm-controller-v1","token":"本机令牌"}`。服务返回版本和游戏连接状态；控制器不会替换游戏连接。

请求 `{"id":1,"op":"exploreMap"}`，响应 `{"id":1,"result":{...}}` 或 `{"id":1,"error":"..."}`。响应按 id 对应；错误、超时不代表动作未发生，先刷新状态再决定是否重试。

仓库自带 Node 22+ 客户端：

```sh
node scripts/game-api.mjs exploreMap '{"areaId":7,"includeFog":true}'
node scripts/game-api.mjs exploreUI
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
| exploreUI | 返回可见节点树、文字、全局位置、尺寸、点击监听标记、revision。上限 1500 节点、24 层，截断会标记 truncated |
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
- 1.4.5 需要重新注入。更新安装与注入分开执行，注入会重启游戏一次。
