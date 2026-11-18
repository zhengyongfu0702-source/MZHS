import SwiftUI
import WebKit
import UIKit

// 网页套壳：直接加载线上域名，所有业务功能都在网页版里，壳只负责显示。
// 网页版自带 Service Worker 离线缓存 + localStorage 登录态，WKWebView 均支持。
struct WebViewContainer: UIViewRepresentable {
    let homeURL = URL(string: "https://736918.top")!

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
        web.load(URLRequest(url: homeURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                             WKScriptMessageHandler,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        weak var webView: WKWebView?

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
