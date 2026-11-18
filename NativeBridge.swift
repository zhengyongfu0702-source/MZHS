import Foundation
import SwiftUI
import UIKit
import WebKit
import AVFoundation

// MARK: - 原生桥接单例：把原生能力的结果送回网页
final class NativeBridge {
    static let shared = NativeBridge()
    weak var webView: WKWebView?

    // 生成安全的 JS 单引号字符串字面量（运单号一般是字母数字，这里仍做完整转义）
    private func jsLiteral(_ s: String) -> String {
        let e = s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "'", with: "\\'")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(e)'"
    }

    // 扫码结果：复制到剪贴板（兜底）+ 尝试填进网页当前可见输入框 + 发自定义事件
    func deliver(code: String) {
        UIPasteboard.general.string = code
        let lit = jsLiteral(code)
        let js = """
        (function(){
          var v = \(lit);
          window.__mzLastScan = v;
          var el = document.activeElement;
          var okTag = el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA');
          var isFile = el && el.tagName === 'INPUT' && el.type === 'file';
          if (!okTag || isFile) {
            var list = document.querySelectorAll('input[type=text],input:not([type]),textarea');
            for (var i=0;i<list.length;i++) {
              var r = list[i].getBoundingClientRect();
              if (r.width > 0 && r.height > 0) { el = list[i]; break; }
            }
          }
          if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
            try {
              el.value = el.value ? (el.value + ' ' + v) : v;
              el.dispatchEvent(new Event('input', {bubbles:true}));
              el.dispatchEvent(new Event('change', {bubbles:true}));
            } catch(e) {}
          }
          try { window.dispatchEvent(new CustomEvent('mzscan', {detail:v})); } catch(e) {}
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - 扫码控制器（AVFoundation）
final class ScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        addCloseButton()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            let label = UILabel(frame: view.bounds)
            label.text = "无法使用相机，请检查权限"
            label.textColor = UIColor.white
            label.textAlignment = .center
            view.addSubview(label)
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr, .ean13, .ean8, .code128, .code39, .code93, .upce, .itf14]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        let hint = UILabel(frame: CGRect(x: 0, y: 96, width: view.bounds.width, height: 28))
        hint.text = "对准运单条形码或二维码"
        hint.textColor = UIColor.white
        hint.font = UIFont.systemFont(ofSize: 14)
        hint.textAlignment = .center
        view.addSubview(hint)

        session.startRunning()
    }

    private func addCloseButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("取消", for: .normal)
        btn.setTitleColor(UIColor.white, for: .normal)
        btn.frame = CGRect(x: 16, y: 48, width: 64, height: 40)
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(btn)
    }

    @objc private func closeTapped() {
        session.stopRunning()
        dismiss(animated: true, completion: nil)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        session.stopRunning()
        dismiss(animated: true) { [weak self] in
            self?.onCode?(value)
        }
    }
}

// MARK: - SwiftUI 包装扫码控制器
struct NativeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScanViewController {
        let vc = ScanViewController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScanViewController, context: Context) {}
}
