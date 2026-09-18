# live_toolbox · AI 直播副驾驶

国内主播 → 境外观众的跨境直播工具。**中文说出去，变英语（后续英/西/葡）**。
一个 App + 可插拔功能包，端侧推理为主，只有 LLM 翻译/应答上云。

> 详细产品口径、平台 API 结论、合规红线、定价、待拍板清单见工作区
> `直播/.workbuddy/memory/MEMORY.md`。本文件只讲**仓库怎么用**。

## 仓库结构

```
live_toolbox/
├── app/       Flutter 前端（端侧：抠像 / 数字人 / TTS / 推流 / 监看）
├── server/    NestJS 后端（账号 / 订阅 / LLM 代理 / 弹幕 WS）—— 规划中，尚未开发
├── docs/      技术方案、任务书
└── _local_junk/  本机产物（apk / 日志 / 截图 / 冻结残留），**不入库**
```

## 为什么是 monorepo

前后端要一起改（比如弹幕协议、AI 应答的 prompt 与端侧兜底），放一个仓库里
改一次提交能保证版本对齐；两边各自独立构建、独立部署，互不干扰。

## app/ · Flutter 前端

- 入口 `app/lib/main.dart`；页面在 `app/lib/pages/`，服务在 `app/lib/services/`。
- 包名 `com.livetoolbox.live_toolbox`，只出 arm64-v8a。
- **`app/build` 是指向 `D:\build_env\live_build` 的 junction**，构建产物不占 C 盘。

### 构建（本机已验证的姿势）

不要用 `flutter.bat`（本机会卡死），直接调 dart 跑 flutter_tools：

```bash
export FLUTTER_ROOT="C:\Users\67332\flutter\flutter" \
       FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
"C:/Users/67332/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe" \
  "C:/Users/67332/flutter/flutter/bin/cache/flutter_tools.snapshot" \
  build apk --release --target-platform android-arm64
```

或直接用现成脚本：`D:\build_env\build_and_wait.py`（启动 + 轮询一体，一次跑完看结果）。

**构建前必做**：`taskkill` 掉残留 `java.exe`（本机内存会被残留 Gradle daemon 吃光，
表现为 Gradle 秒退、零输出）。细节见 `直播/.workbuddy/memory/MEMORY.md`。

## server/ · 后端（尚未开发）

规划中的模块与接口边界见 `server/README.md`。现在只有约定，没有代码。
**端侧零成本，只有 LLM（翻译 + 应答）走服务端** —— 这是订阅制而非买断的原因。

## 约定

- 界面文案**永久中文**（画面里的字幕才是多语言）。
- 不提交密钥/证书（`.gitignore` 已挡）；推流密钥属 bearer secret，加密存、不进日志。
- 不提供任何规避网络管理/风控/造假主体的方法。
