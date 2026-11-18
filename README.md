# 全品类回收统计 · iOS 网页套壳版

这是一个 iOS 网页套壳 App：原生部分只有一个 WKWebView，直接加载线上域名 `https://736918.top`。
所有业务功能（运单、结算、查价、扫码、拍照识别、离线缓存）都在网页版里，网页更新后 App 无需重新编译。

## 编译方式

GitHub Actions 自动编译，产出 ldid 假签名 IPA，供 TrollStore（巨魔）自安装。

## 文件说明（全部在仓库根目录，扁平结构）

- `MeizhuangApp.swift` — App 入口
- `WebViewContainer.swift` — WebView 壳（加载域名 + JS 弹窗 + 相册选图）
- `Info.plist` — 配置（启动页、权限、ATS）
- `AppIcon.png` — App 图标（书签版图标）
- `project.yml` — XcodeGen 工程配置
- `build.yml` — Actions 编译配置（内容需放到 `.github/workflows/build.yml`）

## Bundle ID

`com.zhengyongfu.meizhuang`
