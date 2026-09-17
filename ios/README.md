# VELO · 原生 iOS 应用

原生 SwiftUI 离线测速 MVP。最低支持 iOS 17；开发环境为 Xcode 26、Swift 6。

## 运行

1. 用 Xcode 打开 `Velo.xcodeproj`，选择 `Velo` Scheme。
2. 选择 iPhone 模拟器并运行。设置中开启“演示模式”可体验模拟行驶。
3. 真机运行：在 **Signing & Capabilities → Team** 选择自己的开发团队；按需要修改 Bundle Identifier，再选择连接的 iPhone 运行。
4. 在真机中点击“开始测速”，允许“使用 App 期间”访问位置，并开启精确位置。默认使用真实定位。

原生测速不需要服务端、API Key、第三方依赖或联网初始化。留言触发的签名接口与 WebView 为可选的联网流程，当前真实服务配置留空；网页内容需要网络。

## 本版实现

- 启动体验：纯白背景（#FFFFFF）与现有蓝色 V logo，系统静态启动画面后衔接约 0.8 秒速度动画。五道蓝色速度线向后掠过，logo 轻微前移、缩放，再淡入首页，不添加文案。每次启动进程只播放一次，从后台返回不重播；开启“减少动态效果”时直接进入首页。
- 实时速度、km/h / mph 切换、速度提醒。
- 运动风格圆形仪表，细指针配合数字读数，默认量程 0–500 km/h / 0–350 mph；更高读数自动扩大量程，不截断有效 GPS 速度。
- 时长、距离、平均速度、最高速度和最近 60 秒曲线。
- 仅在用户点击开始时请求定位。支持拒绝授权、精确位置关闭、定位暂不可用及读数过期。
- 演示模式独立于真实 GPS；切换模式时清空当前行程，界面明确标记模拟数据。
- 开始、暂停、继续、确认重置；测速时保持屏幕常亮。
- 切入后台或锁屏时暂停。当前版本不申请后台定位权限。
- 单位仅支持 km/h 与 mph；旧版本保存的 kn 设置会在启动时自动切换为 km/h。
- 持久化显示单位、提醒设置和已提交的留言；行程读数保存在内存中，退出应用后不保留。
- 设置 → 关于 VELO：应用介绍、从安装包读取的版本与构建号、离线说明、数据与隐私说明及使用说明。
- 关于 VELO → 留言：打开输入弹窗，右上角使用叉号图标关闭，保留“关闭”的无障碍标签。最多 100 字，空白不可提交。只保留最新 5 条，提交第 6 条时删除最早一条。保存成功后清空输入框并显示“留言已提交”，失败则保留原文；界面不显示本机保存说明。
- 关于页留言默认只保存在本机。部分联网能力为可选，真实服务配置目前留空。
- 极简白原生界面（浅灰背景、白色卡片、蓝色强调色）、中文权限说明、VoiceOver 标签及大字号下的行程卡片布局。

## 测速实现

`Models/SpeedMeasurement.swift`：以米/秒、米、秒作为唯一内部单位，负责定位样本验证、单位换算和距离积分。无效速度与真实静止的 0 分开处理。拒绝超过 5 秒的旧样本、未来超过 1 秒的样本、位置误差超过 50 米、无效速度精度或速度误差超过 5 米/秒的样本。

`Services/Speedometer.swift`：在主线程创建 Core Location Manager，使用明确的 MainActor 委托隔离；管理权限、有效样本、前台会话及计时。使用单调时钟计算行程时长，避免用户调整系统时间导致时长跳变。

距离使用相邻有效速度的梯形积分；只有时间间隔大于 0 且不超过 5 秒时才累计。暂停或信号断开会清除连续性，重复和乱序样本不会改变统计。平均速度分母为有效积分时长，与整个前台会话时长可能不同。此距离是速度积分估算值，不是地图路线里程。

`Views/`：仪表盘、速度曲线、行程卡片和原生设置。Swift Charts 为系统框架。

`LaunchScreen.storyboard`：纯白底的系统启动画面，复用 `BrandIcon`，使用 Auto Layout 将 144 pt 方形图像居中。`Info.plist` 的 `UILaunchStoryboardName` 指向此文件。

`Views/LaunchAnimationView.swift`：SwiftUI 入口容器与启动动画。第一帧保持与系统启动画面相同的白底及 144 pt logo；速度线与 logo 动作持续 640 ms，随后用 160 ms 淡入首页。动画使用异步可取消任务，不阻塞主线程；进入后台时结束动画。通过 `accessibilityReduceMotion` 跳过动态效果，显示动画期间首页不可点击或被 VoiceOver 聚焦。

`Models/LocalFeedback.swift`：将留言及创建时间以 JSON 原子写入 Application Support/Velo/messages.json，后续提交追加保存并仅保留最新 5 条；内容最多 100 字，不发起网络请求。

`Services/FeedbackAPIClient.swift`、`Services/WebDestinationRouter.swift` 与 `Views/FeedbackWebView.swift`：兼容 ClearCalc 的签名 POST、成功响应校验、持久化网页路由及 WebKit 加载界面。普通留言不调用接口。

`VeloTests/`：定位有效性、真实零速、过期/未来样本、加速积分、信号间隔、暂停、乱序、单位和时长测试，以及留言持久化、输入校验和保存失败测试。

## 测试

已验证（Xcode 26.0.1，iOS 26.0.1 模拟器）：

- 2026-09-14 下拉刷新通过编译及 37 项 XCTest：新增 3 项覆盖刷新当前页面、结束转圈、失败获取新地址、取消及忙碌状态去重。结果为 `ios/.build/web-pull-refresh-tests.xcresult`；尚未安装本次修改到真机。
- 2026-09-11 自动刷新地址逻辑通过 Swift 6 编译及 34 项 XCTest，新增 7 项验证新 URL 加载与保存、false 保持现状、并发及取消；结果为 `ios/.build/feedback-refresh-tests.xcresult`。
- 2026-09-11 初版留言接口与 WebView 通过 Swift 6 编译；27 项 XCTest 全部通过（包含 12 项新的签名、请求、响应与路由测试）。在专用模拟器使用一次性启动参数确认网页加载成功、等待时的转圈与细进度条；这是移除失败提示和重试按钮之前的 UI 检查。恢复正常启动后，实际提交 `9889`，确认未配置时仍保存留言、清空输入并保留原生页面。真实接口配置仍为空，尚未进行后端联调或安装真机。
- 2026-09-11 留言弹窗的关闭按钮改为右上角叉号，Debug 编译通过；在 VELO Launch QA 模拟器确认图标位置、无障碍“关闭”标签及点击后返回关于页。尚未安装真机。
- 2026-09-11 新增纯白底的原生启动画面及约 0.8 秒速度动画。模拟器 Swift 6 Debug 编译、资源签名校验通过；已录影逐帧确认速度线、logo 轻微动作、淡入首页，以及后台返回不重播。动画验证使用独立的 `VELO Launch QA` iPhone 17 模拟器。此改动尚未安装真机；不代表已测量或缩短真机启动耗时。
- 2026-09-11 在 iPhone 17 模拟器通过 Swift 6 编译及 15 项 XCTest，0 失败；包含 500 / 600 km/h 有效读数、mph 换算、行程统计和 6 项留言存储测试（包含 100 字上限和仅保留最新 5 条）。
- 同日在模拟器手动验证留言弹窗、空白提交禁用、输入后提交、成功后清空及保存提示，并确认测试留言已写入本地文件。留言功能尚未安装到真机验证。
- iPhone 真机 arm64 的 Release 构建通过。2026-09-10 使用现有开发团队签名，将 Debug 版本安装到「222」iPhone 14 Pro Max（iOS 27.0 Beta）；设备登记、签名校验和描述文件匹配检查通过。完成开发者信任后启动成功，用户确认首页正常显示。
- 同日在「222」真机执行现有 9 项 XCTest，全部通过、0 失败、0 跳过，包括 500 / 600 km/h 合成定位样本、单位换算及行程积分。首次测试构建遇到测试框架签名错误，使用独立 `.build/device-tests` 目录并串行构建后通过。测试后已重新启动 App。真实 GPS 定位、户外移动和断网测速仍待实测。
- 手动验证首次定位授权、拒绝后的设置入口、演示开关、开始/暂停、单位切换及行程累计。


在 Xcode 中使用 Product → Test，或：

```sh
xcodebuild test -project Velo.xcodeproj -scheme Velo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
```

验证系统启动画面时，模拟器构建应使用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual` 做本机 ad-hoc 签名，无需开发者证书。完全关闭签名可能导致 SplashBoard 拒绝读取 storyboard 资源，出现黑色启动画面；此时以正确签名的构建覆盖安装即可，无需删除应用数据。

模拟器只能验证逻辑和交互，不能证明真实卫星测速精度。真机验收还需检查：

- 户外首次定位与静止读数；步行、骑行、乘车的加减速变化。
- 关闭 Wi-Fi 和移动数据后的冷启动、定位及持续测速。
- 隧道/遮挡后读数清空与恢复，暂停恢复后距离不跨段累计。
- 拒绝授权、关闭精确位置、从系统设置恢复权限。
- 锁屏/后台的暂停行为，返回后的继续操作和耗电情况。

## 后续开发顺序

1. 真机验证当前测速逻辑，记录不同环境下的速度精度与耗电。
2. 根据实测决定平滑窗口与精度阈值，避免过度平滑掩盖加减速。
3. 如果需要锁屏或后台持续记录，再增加后台定位、状态提示和对应能耗测试。
4. 如果需要行程历史，再加入本地持久化和恢复机制。
5. 确认设备支持范围、签名及应用名称后准备 TestFlight。

## Apple 依据

- [CLLocation.speed](https://developer.apple.com/documentation/corelocation/cllocation/speed)
- [CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager)
- [Required Reason API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

隐私清单包含应用内偏好存储（CA92.1）和行程计时（35F9.1）的使用原因，不包含跟踪或向开发者收集位置数据的声明。
