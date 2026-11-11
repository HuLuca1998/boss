# Actions 签名身份

本目录可公开的内容：

- `BossAssistant.cer`：公开证书，不包含私钥。
- `BossAssistant.p12.enc`：加密的证书与私钥包。外层 AES-256-CBC / PBKDF2-SHA256（600000次），内层 PKCS#12 使用同一高熵随机密码并带 MAC 校验，使用兼容 macOS 的编码。

密码仅写入本仓库 GitHub Actions Secret `BOSS_SIGNING_PASSWORD`，不会随 Git 克隆。发布流程 `release.yml` 仅允许 main 的手动运行；PR 检查不导入签名。任何能更改发布工作流且触发运行的维护者，都应被视为拥有签名权限。

`with-signing.py` 从环境取得密码（不打印、不传递给构建子进程），验证固定指纹后执行发布，在 finally 中删除临时钥匙串、解密包并恢复原钥匙串列表。不要将密码放在 YAML、命令参数、日志、Release 或普通 Actions artifact 中。仓库明文私钥忽略规则继续保留。

这是固定自签名身份，不是 Apple Developer ID，不提供公证。新身份为用户明确授权的1.5.2迁移；旧版更新器拒绝新证书，首次必须手动安装 GitHub 正式发布包。之后所有授权 Actions 环境共用这一身份。

密码不可从 GitHub Secret 读回；若该 Secret 丢失，需已有独立备份才能恢复此身份。变更仓库或迁移组织时，必须先完成 Secret 的安全迁移，不能只复制仓库。
