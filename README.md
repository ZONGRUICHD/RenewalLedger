# 续费簿（RenewalLedger）

一个只做续费统计与提醒的 iPhone 应用。适合记录 VPS、服务器、域名、会员和软件服务的月付、季付与年付费用。

## 功能

- 只有两个顶层界面：续费总览、设置。
- 本月 / 本季度 / 今年预计支出，按账期投影每一次续费。
- CNY、USD、HKD、JPY、EUR、GBP 分币种统计，不伪造汇率。
- 默认在到期前 3 天的 09:00 发送本地通知，可调整为 1–30 天及任意时间。
- 搜索、添加、编辑、删除，以及轻扫“已续费”推进到下一账期。
- SwiftData 本地存储；JSON 备份导入与导出。
- iOS 26 原生 SwiftUI，系统组件与克制的 Liquid Glass 自定义层。
- 原生动态数字、符号反馈与触觉反馈；自动遵循“减少动态效果”。
- 浅色、深色和着色三套 App Icon 外观。

## 环境

- iOS 26.0+
- Xcode 26+
- 无第三方依赖、无后端、无账号系统。

在 Xcode 中打开 `RenewalLedger.xcodeproj`，选择你的开发团队与真机即可运行。

## 一次性 GitHub Actions 构建

工作流不会在普通 push、PR 或定时任务时偷跑。它只有两种触发方式：

1. 首次加入或主动修改根目录的 `.release-trigger`（内容是版本号，例如 `1.0.0`），在 `main` 上触发一次；或
2. 打开仓库的 **Actions → Build IPA and publish release**，手动点 **Run workflow**。

工作流使用 Xcode 26 构建设备版，打包未签名 IPA，并创建对应 Release。普通代码提交只要不修改 `.release-trigger`，就不会再次启动 macOS runner。

为控制成本，工作流没有模拟器、依赖下载或重复构建，macOS job 设有 10 分钟硬超时，Linux 预检设有 2 分钟硬超时。若仓库需要按量计费，按 GitHub 当前标准 runner 价格计算，整次流程理论上最多约 0.64 美元；公开仓库使用标准 runner 免费。

> Release 中是未签名 IPA。普通未越狱 iPhone 需要 AltStore / SideStore 或你的 Apple 开发证书重新签名；TrollStore 兼容设备可按其安装方式处理。

## 隐私

续费记录和通知均保存在本机。应用不联网，也不收集价格、备注或账号信息。

## License

MIT
