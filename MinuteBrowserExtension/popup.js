// Popup script - check connection status

async function checkStatus() {
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');

    // Query background for status
    try {
        const response = await chrome.runtime.sendMessage({ type: 'status' });
        if (response && response.connected) {
            statusDot.classList.add('connected');
            statusDot.classList.remove('disconnected');
            statusText.textContent = 'Connected to Minute';
        } else {
            statusDot.classList.add('disconnected');
            statusDot.classList.remove('connected');
            statusText.textContent = response?.error || 'Not connected';
        }
    } catch (error) {
        statusDot.classList.add('disconnected');
        statusDot.classList.remove('connected');
        statusText.textContent = 'Error: ' + error.message;
    }
}

// Check status on popup open
checkStatus();
