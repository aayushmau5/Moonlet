import WebKit

enum WebPageScripts {
    static let hideScrollbars = """
    (() => {
        const style = document.createElement('style');
        style.textContent = 'html, body { overflow: hidden !important; } ::-webkit-scrollbar { display: none; }';
        (document.head || document.documentElement).appendChild(style);
    })();
    """

    static let muteMedia = """
    (() => {
        const mute = (element) => {
            if (element instanceof HTMLMediaElement && !element.muted) {
                element.muted = true;
            }
        };
        document.addEventListener('play', (event) => mute(event.target), true);
        document.addEventListener('volumechange', (event) => mute(event.target), true);
        new MutationObserver(() => {
            document.querySelectorAll('audio, video').forEach(mute);
        }).observe(document, { childList: true, subtree: true });
    })();
    """

    @MainActor
    static func makeConfiguration() -> WKWebViewConfiguration {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: muteMedia, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: hideScrollbars, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = true
        return configuration
    }
}
