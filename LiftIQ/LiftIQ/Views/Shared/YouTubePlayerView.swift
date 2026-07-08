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

        // Load the embed page as a real network navigation. Synthesized HTML
        // (loadHTMLString), even with a remote baseURL, gives the player no
        // genuine referer/origin, which YouTube rejects with "Error 153 —
        // video player configuration error". The embed page sizes its player
        // to the viewport, so no wrapper markup is needed.
        var components = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(videoId)")
        components?.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
            URLQueryItem(name: "rel", value: "0"),
        ]
        guard let url = components?.url else { return }
        webView.load(URLRequest(url: url))
    }
}
