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

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.scrollView.bounces = true
        web.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        web.load(URLRequest(url: homeURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private var imageCompletion: (([URL]?) -> Void)?

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

        // 网页 input[type=file]：相册选图（拍照识别/留档用）
        func webView(_ webView: WKWebView,
                     runJavaScriptOpenPanelWithParameters parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            guard let vc = self.topVC(from: webView) else { completionHandler(nil); return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image"]
            picker.delegate = self
            self.imageCompletion = completionHandler
            vc.present(picker, animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var result: [URL]? = nil
            if let imgURL = info[.imageURL] as? URL {
                result = [imgURL]
            } else {
                let img = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
                if let img = img, let data = img.jpegData(compressionQuality: 0.9) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("mz-\(UUID().uuidString).jpg")
                    try? data.write(to: tmp)
                    result = [tmp]
                }
            }
            picker.dismiss(animated: true)
            let cb = self.imageCompletion
            self.imageCompletion = nil
            cb?(result)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            let cb = self.imageCompletion
            self.imageCompletion = nil
            cb?(nil)
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
