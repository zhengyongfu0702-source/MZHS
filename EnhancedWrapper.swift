import SwiftUI
import UIKit
import LocalAuthentication

// 在网页壳外面包一层原生增强：Face ID 锁 / 原生扫码 / 屏幕常亮。
// 网页版本身不改动，界面保持原样；悬浮工具按钮已按用户要求移除，界面无任何多余元素。
// Face ID 锁在启动时自动验证，不依赖按钮；扫码/常亮代码保留但暂无入口。
struct EnhancedWrapper: View {
    @AppStorage("mz_bio_lock") private var bioLock = false
    @AppStorage("mz_keep_awake") private var keepAwake = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var showTools = false
    @State private var showScanner = false
    @State private var locked = false
    // 防重复弹脸：正在验证中 / 只有真正退到后台回来才需要重新验证
    @State private var authenticating = false
    @State private var needAuthOnActive = false
    @State private var toast = ""

    var body: some View {
        ZStack {
            WebViewContainer()

            // 提示条
            if !self.toast.isEmpty {
                VStack {
                    Spacer()
                    Text(self.toast)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                }
                .allowsHitTesting(false)
            }

            // 锁屏层
            if self.locked {
                lockLayer
            }
        }
        .confirmationDialog("原生工具", isPresented: self.$showTools, titleVisibility: .visible) {
            Button(self.bioLock ? "关闭 Face ID 锁" : "开启 Face ID 锁") {
                self.toggleBioLock()
            }
            Button("扫码录入（原生相机）") {
                self.showScanner = true
            }
            Button(self.keepAwake ? "关闭屏幕常亮" : "开启屏幕常亮") {
                self.toggleAwake()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些都是书签版做不到的原生能力")
        }
        .sheet(isPresented: self.$showScanner) {
            NativeScanner { code in
                NativeBridge.shared.deliver(code: code)
                self.showToast("已录入：\(code)")
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = self.keepAwake
            // 冷启动只验证一次。先盖住页面，避免闪一下数据。
            if self.bioLock {
                self.locked = true
                self.authenticate()
            }
        }
        .onChange(of: self.scenePhase) { phase in
            if phase == .background {
                if self.bioLock {
                    self.locked = true
                    self.needAuthOnActive = true
                }
            } else if phase == .active {
                // 关键修复：只有"真的退到后台再回来"才重新验证。
                // 系统 Face ID 弹窗造成的 inactive -> active 不会置位 needAuthOnActive，
                // 因此不会反复弹出人脸识别。
                if self.needAuthOnActive {
                    self.needAuthOnActive = false
                    self.authenticate()
                }
            }
        }
    }

    private var lockLayer: some View {
        ZStack {
            Color(.secondarySystemBackground)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.accentColor)
                Text("已锁定")
                    .font(.headline)
                Button {
                    self.authenticate()
                } label: {
                    Text("点按解锁")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 11)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func toggleBioLock() {
        if self.bioLock {
            self.bioLock = false
            self.locked = false
            self.needAuthOnActive = false
            self.showToast("已关闭 Face ID 锁")
        } else {
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
                self.showToast("此设备未设置锁屏密码或生物识别")
                return
            }
            self.bioLock = true
            self.showToast("已开启，下次打开需验证")
        }
    }

    private func toggleAwake() {
        self.keepAwake.toggle()
        UIApplication.shared.isIdleTimerDisabled = self.keepAwake
        self.showToast(self.keepAwake ? "屏幕常亮已开启" : "屏幕常亮已关闭")
    }

    // 唯一的验证入口：带"正在验证"闸门，任何情况下都不会并发弹第二次。
    private func authenticate() {
        guard self.bioLock, !self.authenticating else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 设备没有密码/生物识别时不要卡在锁层
            self.locked = false
            return
        }
        self.authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "验证以打开回收统计") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                self.locked = !ok
                if ok { self.needAuthOnActive = false }
            }
        }
    }

    private func showToast(_ msg: String) {
        self.toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            self.toast = ""
        }
    }
}
