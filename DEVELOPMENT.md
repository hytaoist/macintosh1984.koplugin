# 开发与发布

本文档面向修改、构建和维护项目的人。普通安装请阅读
[English README](README.md) 或 [中文说明](README.zh-CN.md)。

## 项目结构

```text
plugin/                          KOReader 插件入口、部署、兼容迁移与 OTA
patches/2-mac1984.lua           稳定用户补丁/加载器
plugin/theme/apply.lua          UI 运行时修改
assets/icons/                   KOReader 图标
assets/simpleui-icons/          SimpleUI 图标包
assets/fonts/                   ChicagoFLF 字体
assets/sponsor/                 微信赞赏码
tests/                          自动化测试
dist/                           构建产物
```

安装后，文件分布在：

```text
koreader/plugins/macintosh1984.koplugin/      新安装的插件目录
koreader/plugins/mac1984-koreader.koplugin/   旧安装目录（仍可升级）
koreader/patches/2-mac1984.lua               用户补丁/加载器
koreader/.mac1984-theme/runtime/apply.lua    兼容旧安装的运行时副本
koreader/.mac1984-theme/backup/              原文件备份
koreader/icons/                              KOReader 图标
koreader/fonts/Mac1984Chicago.ttf            UI 字体
koreader/settings/simpleui/sui_icons/packs/Macintosh 1984/
```

插件只使用 KOReader 的公开模块和用户补丁机制。UI 修改均有 `pcall` 保护。

## 构建

```bash
./build.sh
```

输出：

```text
dist/macintosh1984-v<version>.koplugin.zip     Storefront Release asset
dist/macintosh1984-v<version>.zip              手动安装包
dist/SHA256SUMS
```

Storefront 要求 ZIP 根目录为 `macintosh1984.koplugin/`，且目录内包含 `_meta.lua`。
ZIP 使用固定文件顺序、时间戳和权限，因此重复构建会得到相同的 SHA-256。

## 仓库与目录改名

GitHub 仓库已使用 **Rename** 功能从 `mac1984-koreader` 改为
`macintosh1984.koplugin`。不要新建仓库后删除旧仓库，也不要用旧名称创建其他仓库：
旧 URL 的 301 重定向是已有用户继续通过 Storefront 和插件内 OTA 升级的关键。

插件同时识别新旧目录：

- `macintosh1984.koplugin`：新安装目录，优先级更高。
- `mac1984-koreader.koplugin`：旧安装目录，Storefront 和内置 OTA 会原地升级。

`plugin/compat.lua` 负责冲突检测和旧目录清理；两个目录并存时，新插件会在下次
启动前写入 `plugins_disabled["mac1984-koreader"]`，避免旧副本继续部署资源。
`install.sh` 会在安装新目录时自动移除旧目录，`uninstall.sh` 会同时清理两者。
用户设置键、`.mac1984-theme` 备份目录和 `patches/2-mac1984.lua` 都保持不变。

## 测试

```bash
lua tests/patch_smoke_test.lua plugin/theme/apply.lua
./tests/run_apply_options_test.sh
lua tests/main_test.lua plugin/main.lua
lua tests/ota_test.lua plugin/ota.lua
./tests/run_compat_test.sh
./tests/run_loader_test.sh
./tests/run_deploy_test.sh
./tests/run_installer_test.sh
./tests/run_build_repro_test.sh
python3 tools/check_icons.py
```

测试覆盖插件 UI、OTA、首次部署、重复安装、旧版备份迁移、新旧插件目录共存与清理、
SimpleUI 设置恢复、卸载、AppleDouble 元数据清理、Storefront ZIP 结构、启动快路径、
安全模式、禁用 UI 字体和构建可重复性。`check_icons.py` 会校验 KOReader 图标清单和
SimpleUI 图标引用。
CI 会同时使用 Lua 5.4 和 LuaJIT 运行测试。

## 发布

1. 修改 `plugin/_meta.lua` 和 `assets/simpleui-icons/pack.lua` 中的版本号。
2. 运行完整测试和 `./build.sh`。
3. 提交代码并创建 `v<version>` 标签。
4. 推送标签，`.github/workflows/release.yml` 会构建并创建 GitHub Release。

仓库改名已在 v1.3.0 前完成。发布后请验证旧仓库 URL
`https://github.com/hytaoist/mac1984-koreader` 仍返回 301 重定向，
否则旧版本客户端的 OTA 检查会失效。

也可以运行 `./publish.sh`，但需要本机 `gh` 已完成 GitHub 登录。

## 赞助入口

微信赞赏码由 `plugin/_meta.lua` 中的 `sponsor_wechat_qr` 配置。可选的公开赞助网址由
`sponsor_url` 配置，两者可以独立启用。

## 高级设置

可在 `koreader/settings.reader.lua` 中调整：

```lua
["mac1984_enabled"] = true,
["mac1984_pinstripes"] = false,  -- 关闭标题栏细条纹
["mac1984_shadows"] = false,     -- 关闭窗口硬阴影
["mac1984_ui_font"] = false,     -- 保留 KOReader 默认 UI 字体
["mac1984_safe_mode"] = true,    -- 只替换图标/字体，不修改控件样式
```

前两项可在菜单中即时切换；字体和安全模式需要重启 KOReader。主题不会替换正文字体。
