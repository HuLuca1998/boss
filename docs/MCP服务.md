# 本机 MCP 探索服务

1.4.8 正式 App 内含 `Contents/Resources/ExplorationMCP.mjs`，使用 Node 22+ 和官方 MCP TypeScript SDK，通过 stdio 提供工具。无新增 HTTP 监听端口；内部维持与助手的本机鉴权 WebSocket，重新连接时读取当前端口和令牌，配置和日志不含凭据。不自动重试有副作用的请求，断连后须先检查实际状态。

## 接入 Codex

```sh
codex mcp add boss-assistant -- /opt/homebrew/bin/node /Applications/首领助手.app/Contents/Resources/ExplorationMCP.mjs
```

Node 路径按机器实际安装位置调整。先运行助手、完成注入并进入角色。MCP 进程由调用端启动，无需额外常驻守护程序。正式包中的服务及依赖已合并，不依赖仓库的 node_modules。

工具列表是否立即出现在已有聊天取决于客户端刷新；不能把写入配置当成当前聊天已经热加载成功。当前聊天可使用仓库的协议客户端，实际仍走 MCP 握手、tools/call 和标准结果：

```sh
node mcp/call.mjs game_state
node mcp/call.mjs game_map '{"areaId":7,"includeFog":true}'
node mcp/call.mjs game_watch '{"seconds":5,"intervalMs":1000}'
node mcp/call.mjs game_render '{}' /tmp/game-ui.jpg
```

该仓库客户端需要 `npm ci --prefix mcp` 安装开发依赖；客户端 stderr 显示进度，stdout 仅为结果，不输出图片 base64。

## 工具与传输

| 工具 | 行为 |
| --- | --- |
| game_map | 区域解锁、子地图、事件ID与坐标、完成状态、前置条件、已观测迷雾 |
| game_state | 场景、生命、死亡/自动战斗、附近敌人实体ID/位置/血量和原生寻路状态，只读 |
| game_ui | 过滤3D后的可见2D界面树、窗口列表、文字、父子关系、按钮编号与快照版本，可传viewId聚焦窗口 |
| game_render | 原生 JPEG 作为 MCP image 内容返回；目前3D黑色，仅UI，需窗口截图补足 |
| game_move | 原生位置寻路，结果需再次观察 |
| game_follow | 原生单事件跟随，保留已完成、解锁和事件范围限制 |
| game_click | 使用最近界面快照编号，原生按钮按下/松开流程 |
| game_stop | 退出原生寻路并停止野外自动战斗，之后核验状态 |
| game_watch | 1–30秒持续采样，间隔0.5–5秒；返回真实变化快照。客户端提供 progress token 时发送标准进度通知。取消观察不取消游戏移动，需 game_stop |

另提供 `game://exploration/guide` 只读资源，说明逐步核验流程和当前任务排除项。

操作使用请求/响应，状态采用按需连续观察；不把全量截图不断塞进上下文。`game_watch` 是有边界的观察调用，不是后台无人值守执行循环。stdio 也支持服务器通知，不必为了本机状态观察另开网络服务。远程多客户端场景才需要考虑 Streamable HTTP 及独立认证。

本任务排除方尖碑和聚魂匣；不购买、不分享、不消耗付费资源、不绕过开放与账号保护。`requested=true` 不等于完成。接口底层细节和限制见 [探索API](探索API.md)。

## 验证

```sh
npm ci --prefix mcp
npm test --prefix mcp
node mcp/build.mjs
node mcp/live-test.mjs
node scripts/test-exploration-live.mjs --move
```

模拟测试覆盖真实 SDK 协议握手、工具schema、参数拒绝、错误、图像内容、流式进度和资源读取。live-test 连接已安装正式包和实际游戏；移动实测只允许已经验证的入口附近短距离往返，避免误用到其他位置。新地图采集、宝箱、传送石和Boss成功完成必须等开放后按实际状态验证。

参考：[官方SDK传输说明](https://ts.sdk.modelcontextprotocol.io/server)、[MCP进度通知](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress)、[Codex MCP配置](https://developers.openai.com/codex/mcp)。
