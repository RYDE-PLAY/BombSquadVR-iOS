# iOS VR 升级 worktree 相比 main 的复核

日期：2026-10-09。对比基准：父仓 main `d91f631`，复核代码 `a676bf5`；
Ballistica 子模块从 `291baf835` 更新到 `fdc289b97`，上游基准为 `e55b28ad0`。

## 复核发现

未发现新的 P0/P1 启动或渲染阻断问题。有一处 P2 接口语义遗漏：

- `BombSquadVRBallisticaHost.mm:352` 的 `haveGyro()` 根据 CoreMotion 硬件能力返回 true。
- 上游 `app_platform.h:129` 的契约要求硬件同时向 `Input::PushGyroEvent()` 提供样本。
- 宿主没有这条样本输入链，因此可能误报普通 gyro tilt/parallax 功能可用。
  Cardboard 的头部追踪是另一条链，不受该能力标志影响。
- 建议 VR 宿主返回 false，或者真正补齐普通 Input gyro 数据；当前任务仅记录发现，
  未更改已验证版本，也未重新安装。

## 修改范围与影响

| 修改 | 作用 | 影响及验证边界 |
| --- | --- | --- |
| Ballistica 1.8.0a105 → 1.8.0b12 | 引入新版 Profile、渲染视图、资源及引擎功能 | 会话协议 43 → 53，不能与旧版游戏会话互通；Python/资源/Plus 必须同步更新 |
| 保留双眼渲染入口、drawable FBO、每眼 scissor | 保留原有 iOS Cardboard 的渲染链 | 相比上游的多数 VR 定制来自原 main，并非本次新增；本次衔接渲染性能统计和 main-view 景深范围 |
| Python 3.14.7 / BeeWare pin / zstd 校验 | 与上游依赖一致并保证 native packet codec 可链接 | 固定第三方源码版本；zstd 定义检查在构建期失败，避免晚到应用链接才发现缺库 |
| Plus 缓存签名和 zstd 头路径 | 避免旧的 Plus 适配产物被复用，补齐 native 编译依赖 | 原有 Plus 平台标记改写方法仍然存在，不能由启动结果推断完整账号/联机兼容 |
| Scene 生命周期与保留 GL 视图 | 修复 SDK 27/iOS 27 启动检查；迁移窗口与前后台事件 | 模拟器普通前后台恢复已检查；Scene 被系统断开后重新连接尚未专门验证 |
| 六个 UIKit 桥接方法 | 补齐上游调用的触觉、gyro、浏览器接口 | 能力查询不阻塞主线程；触觉主线程执行；overlay 不支持，URL 用外部浏览器；gyro 只查询、不额外注入引擎倾斜输入 |
| iOS VR 内置键盘覆盖 | Profile 名称、聊天等普通控件在双眼画面中编辑 | 不写入保存偏好；非 VR、其他平台与开发控制台保留原有路径；不新增系统中文输入法 |
| yaw 符号与应用层 recenter | 修正左右方向；以当前视线设参考，消除额外 180° | 最终公式 wrap(heading-reference)；pitch/roll 未改；不重置 Cardboard 融合器，保持姿态连续 |
| Xcode 工程、README、升级记录 | 注册 SceneDelegate/heading helper，记录依赖与结果 | 签名 team、测试 bundle ID 和构建产物未写入工程默认设置 |

## 验证状态

- 真机最新修订构建、安装、启动成功；用户确认归中正常。
- 早期升级版本模拟器双眼主菜单、在线资源下载、前后台恢复成功。
  后续键盘/姿态修订主要在真机检查，不能把早期模拟器结果当成最新全部功能通过。
- 复核再次通过父仓与子模块差异 whitespace check、Python 脚本语法、Info.plist lint。
- 实际 Swift heading helper 检查覆盖五个不同朝向归中后 yaw=0、左右增量符号和两侧 ±π 跨界。
- 待专项验证：Profile 输入提交/取消、聊天、角色纹理预览、二维码换镜片、极端姿态、
  真机前后台与 Scene 重连、手柄/Remote、账号与协议 53 联机、触觉和持续性能。

## 交付限制

子模块 `fdc289b97` 和父仓升级分支当前仅在本机。推送父仓之前必须先让子模块提交
在 fork 上可获取，否则另一台机器不能按 gitlink 初始化。原 main 和原稳定 checkout 未改动。

此复核不执行合并、推送或重新安装应用。
