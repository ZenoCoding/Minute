# Minute Browser Extension Setup

## Install the Extension (Chrome)

1. Open Chrome and go to `chrome://extensions`
2. Enable "Developer mode" (toggle in top-right)
3. Click "Load unpacked"
4. Select the folder: `/Users/tycho/Projects/Minute/MinuteBrowserExtension`
5. Note the **Extension ID** that appears (you'll need this)

## Configure Native Messaging

1. Update the manifest with your extension ID:

```bash
# Edit the file:
nano /Users/tycho/Projects/Minute/MinuteBrowserExtension/com.tychoyoung.minute.browser.json

# Replace EXTENSION_ID_HERE with your actual extension ID
```

2. Copy the manifest to Chrome's native messaging hosts directory:

```bash
mkdir -p ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts
cp /Users/tycho/Projects/Minute/MinuteBrowserExtension/com.tychoyoung.minute.browser.json \
   ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/
```

3. Restart Chrome

## Verify It Works

1. Run the Minute app from Xcode
2. Open Chrome and browse to any website
3. Check the Xcode console for logs like:
   - `BrowserBridge: Context updated - youtube.com`
   - `TrackerService: Committed session Chrome -> Browser [youtube.com]`

## Troubleshooting

- **Extension shows "Not connected"**: Check that the native host script is executable
- **No context file created**: Run `ls ~/Library/Application\ Support/Minute/`
- **Check native host logs**: Run the host manually:
  ```bash
  /Users/tycho/Projects/Minute/MinuteBrowserExtension/native-host/minute-browser-host
  ```

## Files

- `manifest.json` - Extension configuration
- `background.js` - Listens for tab events
- `popup.html/js` - Extension popup UI
- `native-host/minute-browser-host` - Swift script that receives messages
- `com.tychoyoung.minute.browser.json` - Native messaging host manifest
