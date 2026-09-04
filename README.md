# Nexus

Nexus 是一款运行在 macOS 菜单栏中的快捷启动与效率工具。它把应用启动、剪贴板历史、文件搜索、计算器、截图贴图、今日待办、窗口管理和外部插件集中到一个可搜索面板中。

## 系统要求

- macOS 15.2 或更高版本
- Swift 6.2（仅从源码构建时需要）

部分功能需要在“系统设置 → 隐私与安全性”中授权辅助功能、屏幕录制、提醒事项或日历权限。

## 构建与运行

```bash
swift build             # Debug 构建
swift test              # 运行测试
make build              # Release 可执行文件
make bundle             # 创建并签名 build/Nexus.app
make run                # 构建后通过 LaunchServices 启动
```

`make run` 会以应用 Bundle 的身份启动 Nexus，使 macOS TCC 权限正确归属到应用，而不是终端进程。

## 内置功能

- `⌥Space` 呼出搜索面板
- 应用启动与别名管理
- 剪贴板历史与剪贴板贴图
- 文件搜索和计算器
- 截图、OCR、标注与贴图
- 今日待办、日历和提醒事项
- 窗口布局快捷键
- 随机密码插件

快捷键、剪贴板容量、截图目录和 OCR 语言可在设置窗口中调整。

## 插件

在设置窗口的“插件”分区中可以：

- 安装包含 `manifest.json` 的插件文件夹或 ZIP 包
- 启用或停用插件
- 更新已有插件
- 在 Finder 中查看插件目录
- 将第三方插件移到废纸篓

插件以独立子进程运行，入口必须是插件目录中的可执行文件。清单格式如下：

```json
{
  "id": "example",
  "name": "示例插件",
  "keywords": ["example", "示例"],
  "entry": "main.sh",
  "icon": "puzzlepiece.extension",
  "summary": "插件简介"
}
```

入口接收两种命令：

```text
main.sh query "参数"   -> {"items":[...]}
main.sh action "动作" "载荷" -> {"copy":"...","reload":true,"keepOpen":false}
```

在启动器中输入 `@` 可以浏览已启用插件，输入插件关键词可以直接进入插件页面。插件状态保存在 `~/Library/Application Support/Nexus/plugin-state.json`，插件文件位于同目录下的 `Plugins/`。

## 开发说明

源码位于 `Sources/Nexus/`，测试位于 `Tests/NexusTests/`。新增插件功能时，请为解析、匹配、持久化和失败恢复场景补充 Swift Testing 测试。

## 许可

本项目当前未声明开源许可证，代码使用请遵循仓库维护者的授权范围。
