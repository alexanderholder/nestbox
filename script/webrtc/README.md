# WebRTC Recorder

Server-side WebRTC stream recorder using Puppeteer. Used for capturing longer clips from Nest cameras when the API only provides short previews.

## Setup

```bash
cd script/webrtc
npm install
```

## Dependencies

- Node.js 18+
- Puppeteer (installed via npm)
- FFmpeg (for webm → mp4 conversion)

## Usage

Called automatically by `Event::WebrtcRecordable` concern. Not intended for manual use.

```bash
node recorder.js <cameraId> <duration> <outputPath> <apiUrl>
```

## Why Puppeteer?

WebRTC is browser technology. Recording a WebRTC stream server-side requires a headless browser. Puppeteer provides this capability with Chrome/Chromium.
