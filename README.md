# Nestbox

Self-hosted archive for Google Nest camera events. Records clips via WebRTC before they expire.

## Why Nestbox?

Nest only retains event clips for 3 hours without Nest Aware. Nestbox listens for camera events and immediately records the live stream, preserving footage that would otherwise be lost.

<img width="1166" height="703" alt="Screenshot 2026-03-24 at 5 24 23 pm" src="https://github.com/user-attachments/assets/b2c7e31a-4ddd-4ea0-ab05-45ebdcbbf2e5" />

## Features

- Real-time event capture via Pub/Sub (pull or push)
- WebRTC recording directly from camera stream
- Timeline view with filtering by camera and date
- Live camera streaming in browser
- Automatic retry for failed recordings

## Requirements

- Ruby 3.3+
- Node.js 18+ (for WebRTC recording)
- FFmpeg (for video conversion)
- Google Cloud project with Device Access API and Pub/Sub

## Setup

1. Clone and install dependencies:

```
bin/setup
cd script/webrtc && npm install
```

2. Configure Google Cloud credentials in `config/credentials.yml.enc`

3. Start the server and connect via the UI:

```
bin/dev
```

4. Visit http://localhost:3001 and connect your Nest account. Cameras sync automatically.

## How it works

Nestbox receives events from Google Nest via Cloud Pub/Sub (either pull polling or push webhooks). When an event occurs—motion, person, sound, or doorbell, it connects to the camera's WebRTC stream and records directly from the source.

## Development

```
bin/dev
```

This starts the Rails server and Solid Queue for background jobs.

## Built with

Rails 8, Solid Queue, Hotwire, and Puppeteer for WebRTC recording.

## Disclaimer

This project is not affiliated with, endorsed by, or connected to Google or Nest Labs. "Nest" is a trademark of Google LLC.

This software is provided for personal and educational use only. Users are responsible for ensuring their use complies with Google's [Device Access API Terms of Service](https://developers.google.com/nest/device-access/tos) and any applicable laws.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. USE AT YOUR OWN RISK.
