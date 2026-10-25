# 首领助手开发目录

支持环境、功能、权限和使用说明见 [项目 README](../README.md)，发布与测试见 [发布与更新](../docs/发布与更新.md)。

- Sources：SwiftUI 应用、本机桥、键盘、事件与更新客户端。
- Resources/Runtime.js：适配游戏 1.16.3 的控制脚本，仅明确重新注入时更新游戏缓存并重启游戏。
- Resources/OriginalCache.bin：与 Injector.originalHash 匹配的原始缓存，注入与还原所需。
- Updater：固定签名验证、等待正常退出、安装和失败回滚，不重启游戏。
- Tests：键盘、恢复、场景、弹窗、红包与更新策略测试。
- VERSION / BUILD_NUMBER：版本号和递增构建号。
- SigningIdentity.txt：证书公开指纹，私钥只保存在登录钥匙串。
- Validation.json：验证记录，历史结论按对应版本字段阅读。

默认构建输出 build/首领助手.app；APP_OUT、APP_VERSION、APP_BUILD 用于隔离发布或本地更新基线。正式发布必须匹配已提交的 VERSION。证书不可用则失败，禁止退回临时签名。

ESC 按游戏 GetOpenViewOrder 选择最上层页面，排除已确认的被动提示层，调用原始 CommonTab2/3SubView、CommonBg2/3SubView、LotteryShopView 或普通空白关闭处理。根页面必须匹配。BagView 和 StoreView 直接继承 BaseView，不能只按 BaseMultiActivityView 分类。每按一次执行一层，输入文字时不处理，自定义确认、购买、领取回调不作为返回。

本机 analysis 目录、构建产物、现场观测、旧 App 与连接凭据不纳入 Git。
