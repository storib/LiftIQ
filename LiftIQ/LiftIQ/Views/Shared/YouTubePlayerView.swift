import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool = false

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : .all

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let autoplayParam = autoplay ? 1 : 0
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
            * { margin: 0; padding: 0; }
            html, body { width: 100%; height: 100%; background: #000; }
            iframe { width: 100%; height: 100%; border: none; }
        </style>
        </head>
        <body>
        <iframe
            src="https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=\(autoplayParam)&rel=0&modestbranding=1"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
