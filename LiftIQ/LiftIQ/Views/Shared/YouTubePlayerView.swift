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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedVideoId: String?
        var loadedAutoplay: Bool?
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // updateUIView runs on every SwiftUI update of an ancestor; reloading
        // the embed unconditionally restarts the video mid-playback.
        guard context.coordinator.loadedVideoId != videoId ||
              context.coordinator.loadedAutoplay != autoplay else { return }
        context.coordinator.loadedVideoId = videoId
        context.coordinator.loadedAutoplay = autoplay

        // Load our Firebase-Hosted wrapper page, which iframes the video from
        // a genuine https origin. YouTube requires a valid HTTP Referer on
        // embed requests and rejects referer-less playback with "Error 153 —
        // video player configuration error"; both a direct top-level load of
        // /embed/<id> and synthesized HTML (loadHTMLString, even with a remote
        // baseURL) fail that check. The wrapper's iframe request carries the
        // hosting origin as referer, which YouTube accepts. Wrapper source:
        // firebase/hosting/embed.html (deploy with `firebase deploy --only hosting`).
        var components = URLComponents(string: "https://trainai-3d40a.web.app/embed.html")
        components?.queryItems = [
            URLQueryItem(name: "v", value: videoId),
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
        ]
        guard let url = components?.url else { return }
        webView.load(URLRequest(url: url))
    }
}
