// Minute Browser Extension - Content Script
// Extracts rich page context for AI task inference

(function () {
    // Avoid running multiple times
    if (window.__minuteContentScriptLoaded) return;
    window.__minuteContentScriptLoaded = true;

    // Extract page metadata
    function getMetaContent(name) {
        const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
        return meta ? meta.getAttribute('content') : null;
    }

    // Extract main content text (first 500 chars)
    function getContentSnippet() {
        // Try semantic elements first
        const main = document.querySelector('main, article, [role="main"]');
        const target = main || document.body;

        // Get text content, clean up whitespace
        let text = target.innerText || '';
        text = text.replace(/\s+/g, ' ').trim();

        // Limit to 500 chars
        return text.substring(0, 500);
    }

    // Get currently selected text
    function getSelectedText() {
        const selection = window.getSelection();
        return selection ? selection.toString().trim() : '';
    }

    // Build context object
    function extractContext() {
        return {
            // URL components
            path: window.location.pathname,
            query: window.location.search,
            hash: window.location.hash,

            // Meta tags
            description: getMetaContent('description'),
            keywords: getMetaContent('keywords'),

            // OpenGraph
            ogType: getMetaContent('og:type'),
            ogTitle: getMetaContent('og:title'),
            ogDescription: getMetaContent('og:description'),
            ogSiteName: getMetaContent('og:site_name'),

            // Twitter Card
            twitterCard: getMetaContent('twitter:card'),

            // Content
            contentSnippet: getContentSnippet(),
            selectedText: getSelectedText(),

            // Page metadata
            lang: document.documentElement.lang || null,
            canonical: document.querySelector('link[rel="canonical"]')?.href || null
        };
    }

    // Send context to background script
    function sendContext() {
        try {
            const context = extractContext();
            chrome.runtime.sendMessage({
                type: 'page_context',
                context: context
            }, (response) => {
                // Handle potential errors (background not ready)
                if (chrome.runtime.lastError) {
                    // Silently ignore - background may not be ready yet
                    console.debug("Minute: Background not ready", chrome.runtime.lastError.message);
                }
            });
        } catch (e) {
            console.debug("Minute: Error sending context", e);
        }
    }

    // Send on load
    if (document.readyState === 'complete') {
        sendContext();
    } else {
        window.addEventListener('load', sendContext);
    }

    // Re-send on significant DOM changes (SPA navigation)
    let lastPath = window.location.pathname;
    const observer = new MutationObserver(() => {
        if (window.location.pathname !== lastPath) {
            lastPath = window.location.pathname;
            setTimeout(sendContext, 500); // Delay for content to load
        }
    });

    observer.observe(document.body, {
        childList: true,
        subtree: true
    });

    // Send updated context when user selects text
    document.addEventListener('mouseup', () => {
        const selected = getSelectedText();
        if (selected.length > 10) {
            chrome.runtime.sendMessage({
                type: 'selection',
                selectedText: selected.substring(0, 500)
            });
        }
    });
})();
