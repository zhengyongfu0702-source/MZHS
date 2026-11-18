import SwiftUI
import UIKit
import LocalAuthentication

// 在网页壳外面包一层原生增强：Face ID 锁 / 原生扫码 / 屏幕常亮。
// 网页版本身不改动，界面保持原样，只多一个右上角悬浮工具钮。
struct EnhancedWrapper: View {
    @AppStorage("mz_bio_lock") private var bioLock = false
    @AppStorage("mz_keep_awake") private var keepAwake = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var showTools = false
    @State private var showScanner = false
    @State private var locked = false
    @State private var toast = ""

    var body: some View {
        ZStack {
            WebViewContainer()

            // 右上角悬浮工具钮（不遮挡网页内容，半透明）
            VStack {
                HStack {
                    Spacer()
                    Button {
                        self.showTools = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.42))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 14)
                    .padding(.top, 10)
                }
                Spacer()
            }

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
            self.requestAuthIfNeeded()
        }
        .onChange(of: self.scenePhase) { phase in
            if phase == .active {
                self.requestAuthIfNeeded()
            } else if phase == .background {
                if self.bioLock { self.locked = true }
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
                    self.requestAuthIfNeeded()
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

    private func requestAuthIfNeeded() {
        guard self.bioLock else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            self.locked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "验证以打开回收统计") { ok, _ in
            DispatchQueue.main.async {
                self.locked = !ok
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
