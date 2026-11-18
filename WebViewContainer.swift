import SwiftUI
import WebKit
import UIKit

// 网页套壳：优先直接加载线上站点，与 Safari 书签版完全同源、同页面、同显示逻辑。
// 上一版用 loadHTMLString 内置整页 + 导航拦截，导致真机首屏白屏，已废弃。
// 现在线上优先：有网就是书签版本身（已验证正常显示）；离线由网页自带 Service Worker 提供缓存；
// 只有主文档彻底加载失败（离线且无缓存）才回退到内置 HTML 副本，保证至少有界面可看。
// 原生增强（Face ID / 扫码 / 常亮）在 EnhancedWrapper，与本容器互不干扰。
struct WebViewContainer: UIViewRepresentable {
    static let homeURL = URL(string: "https://736918.top/")!

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // 拦截网页里 input[type=file] 的点击，改走原生相册（绕开新版 SDK 对选图代理的 iOS 18.4 限制）
        let hook = """
        (function(){
          if (window.__mzHookInstalled) return;
          window.__mzHookInstalled = true;
          document.addEventListener('click', function(e){
            var t = e.target;
            if (t && t.tagName === 'INPUT' && t.type === 'file') {
              e.preventDefault();
              e.stopPropagation();
              window.__mzPickInput = t;
              try { window.webkit.messageHandlers.mzPickImage.postMessage({}); } catch(err) {}
            }
          }, true);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: hook, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        config.userContentController.add(context.coordinator, name: "mzPickImage")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.scrollView.bounces = true
        web.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        context.coordinator.webView = web
        NativeBridge.shared.webView = web
        // 直接加载线上首页：与书签版完全一致，不再用内置 HTML 当首屏
        web.load(URLRequest(url: WebViewContainer.homeURL,
                            cachePolicy: .useProtocolCachePolicy,
                            timeoutInterval: 20))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // 从 APP Bundle 读内置网页（仅作离线兜底）；读不到时给明确提示页，而不是白屏
    static func bundledHTML() -> String {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            return html
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font:16px -apple-system,sans-serif;padding:32px;color:#333}
        b{color:#c00}</style></head><body>
        <h3>当前无网络</h3><p>请连接网络后重新打开。内置页面未找到时请确认 index.html 已打进 APP。</p>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                             WKScriptMessageHandler,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        weak var webView: WKWebView?
        // 只回退一次，避免内置页再失败时来回弹
        private var didFallback = false

        // 主文档加载失败（离线且无 Service Worker 缓存）才回退内置页，杜绝白屏。
        // 注意：这里不拦截任何正常导航，描述文件/APK/外链都放行。
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard !self.didFallback else { return }
            self.didFallback = true
            webView.loadHTMLString(WebViewContainer.bundledHTML(), baseURL: WebViewContainer.homeURL)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            guard !self.didFallback else { return }
            self.didFallback = true
            webView.loadHTMLString(WebViewContainer.bundledHTML(), baseURL: WebViewContainer.homeURL)
        }

        // JS alert
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            guard let vc = self.topVC(from: webView) else { completionHandler(); return }
            let ac = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            vc.present(ac, animated: true)
        }

        // JS confirm
        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            guard let vc = self.topVC(from: webView) else { completionHandler(false); return }
            let ac = UIAlertController(title: "确认", message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            ac.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            vc.present(ac, animated: true)
        }

        // JS prompt
        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard let vc = self.topVC(from: webView) else { completionHandler(nil); return }
            let ac = UIAlertController(title: "输入", message: prompt, preferredStyle: .alert)
            ac.addTextField { tf in tf.text = defaultText }
            ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            ac.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler(ac.textFields?.first?.text)
            })
            vc.present(ac, animated: true)
        }

        // 收到网页选图请求 -> 弹系统相册
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "mzPickImage", let web = self.webView else { return }
            guard let vc = self.topVC(from: web) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image"]
            picker.delegate = self
            vc.present(picker, animated: true)
        }

        // 相册选完 -> 把图片塞回网页的 input 并触发 change
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
            guard let img = img,
                  let data = img.jpegData(compressionQuality: 0.9),
                  let web = self.webView else { return }
            let b64 = data.base64EncodedString()
            let js = """
            (function(){
              var input = window.__mzPickInput;
              window.__mzPickInput = null;
              if (!input) return;
              try {
                var bin = atob('\(b64)');
                var arr = new Uint8Array(bin.length);
                for (var i=0;i<bin.length;i++) arr[i]=bin.charCodeAt(i);
                var file = new File([arr], 'mz-photo.jpg', {type:'image/jpeg'});
                if (typeof DataTransfer !== 'undefined') {
                  var dt = new DataTransfer();
                  dt.items.add(file);
                  input.files = dt.files;
                }
                input.dispatchEvent(new Event('change', {bubbles:true}));
              } catch(e) { console.error('mz pick', e); }
            })();
            """
            web.evaluateJavaScript(js, completionHandler: nil)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        private func topVC(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return view.window?.rootViewController
        }
    }
}
