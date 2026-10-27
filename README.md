# TrayCal —— Windows 右下角托盘日程日历

点任务栏右下角的托盘图标 → 弹出月历 → 直接添加/编辑/删除日程 → 到点右下角弹提醒。
**纯本地、零账号、零安装、离线可用**——不连任何云服务，不依赖 Outlook。

## 为什么做这个

Windows 11 自带"点时钟弹出日历"只能看不能加，还得登录微软账号（经常"连接失败"）。
TrayCal 把手机日历"点一下记日程"的体验搬回桌面，体积小到可以忽略。

## 快速开始

```
1. clone 或下载本仓库任意目录
2. 双击 src\启动TrayCal.vbs（无黑窗；或右键 src\TrayCal.ps1 → 使用 PowerShell 运行）
3. 托盘出现日历图标 → 左键单击弹出面板
```

要求：Windows 10/11 + 系统自带 PowerShell 5.1。**不需要安装任何东西。**

## 功能

| 功能 | 操作 |
|------|------|
| 查看月历 | 左键托盘图标，面板从右下角弹出；点面板外自动收起 |
| 切换月份/年份 | 鼠标悬停日历滚动滚轮切换；点标题在"日→月→年"视图间循环切换；左右箭头按当前视图单位步进 |
| 有日程的日期 | 日期下方显示蓝色小圆点 |
| 添加日程 | 点日期 → "添加日程" → 标题必填；时间用"时/分"两栏下拉（5 分钟一档，分钟可手输），或勾选"全天" |
| 定时提醒 | 带时间的日程到点：右下角弹窗（知道了 / 稍后10分钟）+ 提示音 |
| 全天事项 | 只列在当天列表，不提醒 |
| 编辑 / 删除 | 选中列表项点按钮，或双击列表项编辑；删除有确认 |
| 复制本周→下周 | 面板日期行右侧按钮：把选中日期所在周（周一~周日）的日程整体复制到下一周，新记录重置提醒状态 |
| 开机自启 | 右键托盘图标 → 勾选"开机自启" |
| 查看数据 | 右键托盘图标 → "打开日程文件" |

## 数据

全部日程存在 `data/events.json`（UTF-8，可直接手改，重启后生效）：

```json
{ "version": 1, "events": [
  { "id": "a1b2c3d4e5f6", "title": "和XX开会", "date": "2026-10-27",
    "time": "14:00", "reminded": false, "snoozeUntil": null }
] }
```

- `time` 为 `null` 表示全天事项
- 备份/迁移 = 拷走这个文件；本文件不入库（.gitignore 已排除 data/）

## 卸载

关闭 TrayCal（托盘右键 → 退出）→ 删除文件夹。无注册表、无残留（开机自启开启时会留一个快捷方式，可在托盘菜单关掉或删除 `shell:startup` 里的 TrayCal.lnk）。

## 资源占用（实测，Windows 11 / PS 5.1）

- 常驻内存 ≈ 90~110MB（powershell.exe 宿主开销为主）
- 空闲 CPU ≈ 0%（定时器每 20 秒扫一次日程表）
- 磁盘 < 100KB

## 开发自测

```
powershell -File src\TrayCal.ps1 -SelfTest       # 数据层断言（含周/复制/批量逻辑）
powershell -File src\TrayCal.ps1 -Show           # 启动并自动弹出面板（截图/演示用）
powershell -File src\TrayCal.ps1 -Demo           # 连添加对话框一起弹出
powershell -File src\TrayCal.ps1 -DemoReminder   # 弹一条测试提醒
powershell -File src\TrayCal.ps1 -DemoCalMonth   # 月历初始为"月选择"视图
powershell -File src\TrayCal.ps1 -DemoCalYear    # 月历初始为"年选择"视图
```

界面异常不会弹 .NET 崩溃窗：统一兜底写日志到 `src/data/traycal.log`。

## 已知边界（v1）

- 不做云同步 / 手机同步（设计决策，见《需求文档.md》D3）
- 无重复日程、农历、多档提前提醒（列入 P2 计划）
- Win11 新式托盘可能把图标收进 `∧` 溢出区，拖出来即可常驻

## 项目文件

| 文件 | 作用 |
|------|------|
| src/TrayCal.ps1 | 入口：参数、单实例、模块加载、托盘与消息循环 |
| src/lib/data.ps1 | 数据层：读写、复制/覆盖、批量生成（纯函数） |
| src/lib/ui-panel.ps1 | 主面板与自绘月历（三视图/拖选/滚轮） |
| src/lib/ui-dialogs.ps1 | 添加编辑、批量添加、批量删除对话框 |
| src/lib/ui-reminder.ps1 | 提醒窗与定时扫描 |
| src/tests/SelfTest.ps1 | 数据层自测（-SelfTest 触发） |
| src/启动TrayCal.vbs | 静默启动器（无控制台窗口） |
| src/assets/note.png | 托盘图标素材 |
| 需求文档.md / 开发方案.md | 需求与技术方案 |

## License

个人自用工具，随意参考修改。
