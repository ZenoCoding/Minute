// Minute Browser Extension - Background Service Worker
// Sends rich page context to native Minute app via Native Messaging

const NATIVE_HOST_NAME = "com.tychoyoung.minute.browser";

// State
let isConnected = false;
let nativePort = null;
let lastSentKey = null;
let lastError = null;
let currentContext = null;  // Latest context from content script

// Connect to native app
function connectToNative() {
  try {
    console.log("Minute: Attempting to connect to native host...");
    nativePort = chrome.runtime.connectNative(NATIVE_HOST_NAME);

    nativePort.onMessage.addListener((message) => {
      console.log("Minute: Received from native:", message);
      isConnected = true;
      lastError = null;
    });

    nativePort.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError;
      lastError = error ? error.message : "Disconnected";
      console.log("Minute: Disconnected from native app:", lastError);
      isConnected = false;
      nativePort = null;

      // Retry connection after delay
      setTimeout(connectToNative, 5000);
    });

    console.log("Minute: Connected to native app");
    isConnected = true;
  } catch (error) {
    console.error("Minute: Failed to connect to native app:", error);
    lastError = error.message;
    isConnected = false;
  }
}

// Handle messages from popup and content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'status') {
    sendResponse({
      connected: isConnected,
      error: lastError
    });
    return true;
  }

  if (message.type === 'page_context') {
    // Rich context from content script - store and send immediately
    currentContext = message.context;
    console.log("Minute: Received page context:", currentContext?.path,
      currentContext?.contentSnippet ? `(${currentContext.contentSnippet.length} chars)` : "(no snippet)");

    // Send to native immediately if we have the tab info
    if (sender.tab) {
      sendTabInfoWithContext(sender.tab, currentContext);
    }
  }

  if (message.type === 'selection') {
    // User selected text
    if (currentContext) {
      currentContext.selectedText = message.selectedText;
    }
  }

  return true;
});

// Send tab info with rich context to native app
function sendTabInfo(tab) {
  if (!tab || !tab.url) return;

  // Skip chrome:// and extension pages
  if (tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://")) {
    return;
  }

  try {
    const url = new URL(tab.url);
    const domain = url.hostname;
    const path = url.pathname;
    const title = tab.title || "";

    // Dedupe: don't send if same domain+path+title
    const key = `${domain}${path}|${title}`;
    if (key === lastSentKey) return;
    lastSentKey = key;

    // Build rich message
    const message = {
      type: "tab_context",
      domain: domain,
      path: path,
      query: url.search,
      title: title,
      timestamp: Date.now(),

      // Rich context from content script (may be null initially)
      description: currentContext?.description || null,
      keywords: currentContext?.keywords || null,
      ogType: currentContext?.ogType || null,
      ogTitle: currentContext?.ogTitle || null,
      ogDescription: currentContext?.ogDescription || null,
      ogSiteName: currentContext?.ogSiteName || null,
      contentSnippet: currentContext?.contentSnippet || null,
      selectedText: currentContext?.selectedText || null,
      lang: currentContext?.lang || null
    };

    if (nativePort && isConnected) {
      nativePort.postMessage(message);
      console.log("Minute: Sent rich context:", domain + path,
        message.contentSnippet ? `(${message.contentSnippet.length} chars)` : "(no content)");
    } else {
      console.log("Minute: Not connected, queuing:", domain);
    }

    // Clear context after sending (will be refreshed by content script)
    currentContext = null;
  } catch (error) {
    console.error("Minute: Error parsing tab URL:", error);
  }
}

// Send tab info with explicitly provided context (from content script)
function sendTabInfoWithContext(tab, context) {
  if (!tab || !tab.url) return;

  // Skip chrome:// and extension pages
  if (tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://")) {
    return;
  }

  try {
    const url = new URL(tab.url);
    const domain = url.hostname;
    const path = url.pathname;
    const title = tab.title || "";

    // Build rich message with provided context
    const message = {
      type: "tab_context",
      domain: domain,
      path: path,
      query: url.search,
      title: title,
      timestamp: Date.now(),

      // Rich context from content script
      description: context?.description || null,
      keywords: context?.keywords || null,
      ogType: context?.ogType || null,
      ogTitle: context?.ogTitle || null,
      ogDescription: context?.ogDescription || null,
      ogSiteName: context?.ogSiteName || null,
      contentSnippet: context?.contentSnippet || null,
      selectedText: context?.selectedText || null,
      lang: context?.lang || null
    };

    if (nativePort && isConnected) {
      nativePort.postMessage(message);
      console.log("Minute: Sent rich context (immediate):", domain + path,
        message.contentSnippet ? `(${message.contentSnippet.length} chars)` : "(no content)");
    } else {
      console.log("Minute: Not connected, queuing:", domain);
    }
  } catch (error) {
    console.error("Minute: Error parsing tab URL:", error);
  }
}

// Listen for tab activation (switching tabs)
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    // Small delay to let content script run
    setTimeout(() => sendTabInfo(tab), 100);
  } catch (error) {
    console.error("Minute: Error getting activated tab:", error);
  }
});

// Listen for tab updates (URL changes, title changes)
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // Only care about the active tab
  if (!tab.active) return;

  // Send on URL or title change
  if (changeInfo.url || changeInfo.title) {
    // Small delay to let content script run
    setTimeout(() => sendTabInfo(tab), 200);
  }
});

// Listen for window focus changes
chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;

  try {
    const [tab] = await chrome.tabs.query({ active: true, windowId: windowId });
    if (tab) {
      setTimeout(() => sendTabInfo(tab), 100);
    }
  } catch (error) {
    console.error("Minute: Error getting focused window tab:", error);
  }
});

// Initialize
connectToNative();

// Send current tab on startup
chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  if (tabs[0]) {
    setTimeout(() => sendTabInfo(tabs[0]), 500);
  }
});

console.log("Minute Browser Extension v1.1 loaded (rich context)");
