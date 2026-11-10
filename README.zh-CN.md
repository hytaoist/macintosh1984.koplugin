# Macintosh 1984 for KOReader

[English](README.md) | **简体中文**

为任何能够运行 KOReader 的设备带来 Macintosh 1984 的黑白界面，并支持 KOReader 与 SimpleUI。

- Storefront 安装与更新
- 通过 GitHub Releases 手动检查和安装更新

[下载最新版本](https://github.com/hytaoist/macintosh1984.koplugin/releases/latest)

![Macintosh 1984 for KOReader](preview/mac1984-ui.png)

## 使用要求

- 设备能够运行 KOReader
- 已安装 KOReader；当前验证版本为 `v2026.07.2`
- SimpleUI `3.0` 为可选增强，不是运行主题的必需条件

其他设备和 KOReader 版本可能可以使用，但尚未经过完整验证。

## 主要功能

- 103 个针对高分辨率电子墨水屏优化的 KOReader 图标
- 34 个 SimpleUI 图标，并自动切换为 ChicagoFLF 字体
- 经典条纹标题栏、方形窗口、硬阴影和圆角按钮
- 不修改 KOReader 核心 Lua 源码；替换的文件均有备份，可从菜单恢复

<details>
<summary>查看完整图标集</summary>

![KOReader 图标](preview/icon-sheet.png)

![SimpleUI 图标](preview/simpleui-icon-sheet.png)

</details>

## 安装

### Storefront（推荐）

1. 打开 KOReader 的 **Storefront**。
2. 搜索 **Macintosh 1984**，或输入仓库 `hytaoist/macintosh1984.koplugin`。
3. 安装后完全退出并重新打开 KOReader。

以后在 Storefront 中执行 **Update All** 即可更新。

### 手动安装

下载最新版 `macintosh1984-v*.koplugin.zip`，解压到 `koreader/plugins/`，最终目录应为：

```text
koreader/plugins/macintosh1984.koplugin/
```

也可以在电脑上挂载设备存储后运行：

```bash
./install.sh /path/to/mounted-device
```

安装完成后，完全退出 KOReader 再重新打开。如果主题没有出现，请确认 KOReader
已完全退出，而不是只退出了应用界面。如果只能看到插件菜单，请打开
**工具 → Macintosh 1984 → Theme diagnostics** 查看诊断信息。

当前版本在 KOReader 跳过或禁用启动用户补丁时，会自动使用兼容后备方式加载主题。

### 从 `mac1984-koreader.koplugin` 升级

已有的 Storefront 安装可以直接使用 **Update All**；Storefront 会继续更新当前
已安装的目录。插件内的 **Check for updates** 也会通过 GitHub 的仓库重命名跳转
自动升级。

如果是手动并排安装，解压新包后请删除旧的
`koreader/plugins/mac1984-koreader.koplugin/` 目录。`install.sh` 会自动完成清理。
若两个目录同时存在，新插件会优先生效，在下次启动时停用旧目录，并在菜单中提供
**Remove old plugin folder**。用户设置和 `.mac1984-theme` 中的原文件备份都会保留。

## 更新

- Storefront 用户：**Storefront → Update All**
- 手动安装用户：**工具 → Macintosh 1984 → Check for updates**

手动更新会先用 Release 附带的 SHA-256 校验和验证下载包；如果更新被意外中断，
下次启动会自动恢复旧版插件目录。

更新后按提示重启 KOReader。

## 插件菜单

在 **工具 → Macintosh 1984** 中可以：

- 即时切换标题栏细条纹和窗口硬阴影
- 在 ChicagoFLF 与系统 UI 字体之间切换，或启用安全模式（需重启）
- 重新安装或修复主题文件
- 检查更新
- 停用主题并恢复原文件
- 查看启动补丁与主题运行时诊断
- 查看版本与关于信息

## 赞助

如果这个主题对你有帮助，可以在以下位置扫码支持后续维护：

**工具 → Macintosh 1984 → About → Sponsor this project → Show WeChat reward code**

## 恢复与卸载

推荐先执行：

**工具 → Macintosh 1984 → Disable and restore original files**

然后从 Storefront 或 `koreader/plugins/` 中删除插件。也可以运行：

```bash
./uninstall.sh /path/to/mounted-device
```

## 更多

构建、测试、部署结构和高级设置见 [DEVELOPMENT.md](DEVELOPMENT.md)。

这是非官方粉丝主题，与 Apple 或 KOReader 项目没有隶属关系。代码使用 MIT
许可，图标使用 CC0；字体许可见 `assets/fonts/LICENSE-ChicagoFLF.txt`。
