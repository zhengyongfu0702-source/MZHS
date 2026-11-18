import SwiftUI
import WebKit
import UIKit

// 更保险的离线方案：
// 页面外壳（index.html，JS/CSS 全内联）内置进 APP，永远从本地加载，断网冷启动也秒开、绝不白屏。
// baseURL 固定为线上域名 -> localStorage / 缓存数据与线上同 origin，离线快照、登录态稳定可用。
// 数据请求（fetch /api/*、/.cloud/*）走相对路径：联网时到线上，离线时网页自带的离线逻辑接管。
// 网页里的整页跳转（location.reload / location.replace(?_r=)）会被导航拦截，全部改回内置加载。
struct WebViewContainer: UIViewRepresentable {
    static let baseURL = URL(string: "https://736918.top/")!

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
        // 页面外壳永远从内置 HTML 加载（与网络无关）
        loadBundledPage(into: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // 从 APP Bundle 读内置网页；读不到时给一个明确提示页，而不是白屏
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
        <h3>内置页面未找到</h3><p>请重新编译安装，确认 index.html 已打进 APP。</p>
        </body></html>
        """
    }

    func loadBundledPage(into web: WKWebView) {
        web.loadHTMLString(WebViewContainer.bundledHTML(), baseURL: WebViewContainer.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                             WKScriptMessageHandler,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        weak var webView: WKWebView?

        // 拦截整页级导航：任何对首页的 reload / location.replace(?_r=) /
        // 重新导航到域名首页的请求，一律取消并改回内置 HTML，杜绝离线白屏与自动更新循环。
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let isMain = navigationAction.targetFrame?.isMainFrame ?? true
            let host = url.host?.lowercased() ?? ""
            let isHome = host == "736918.top" || host == "www.736918.top"
            if isMain && isHome && (url.path.isEmpty || url.path == "/") {
                decisionHandler(.cancel)
                loadBundled(into: webView)
                return
            }
            // 其它导航：安装描述文件、下载 APK、外部链接等正常放行
            decisionHandler(.allow)
        }

        private func loadBundled(into web: WKWebView) {
            web.loadHTMLString(WebViewContainer.bundledHTML(), baseURL: WebViewContainer.baseURL)
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
