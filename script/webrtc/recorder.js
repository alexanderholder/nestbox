const puppeteer = require("puppeteer")
const fs = require("fs")

const [deviceId, duration, outputPath, accessToken, projectId] = process.argv.slice(2)

if (!deviceId || !duration || !outputPath || !accessToken || !projectId) {
  console.error("Usage: node recorder.js <deviceId> <duration> <outputPath> <accessToken> <projectId>")
  process.exit(1)
}

const NEST_API_URL = `https://smartdevicemanagement.googleapis.com/v1/enterprises/${projectId}/devices/${deviceId}:executeCommand`
const TRACK_TIMEOUT_MS = 20000

async function record() {
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      "--use-fake-ui-for-media-stream",
      "--no-sandbox",
      "--disable-setuid-sandbox"
    ]
  })

  try {
    const page = await browser.newPage()

    const chunks = await page.evaluate(async (nestApiUrl, accessToken, durationSecs, trackTimeoutMs) => {
      const pc = new RTCPeerConnection({
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
      })

      pc.addTransceiver("audio", { direction: "recvonly" })
      pc.addTransceiver("video", { direction: "recvonly" })
      pc.createDataChannel("dataSendChannel")

      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)

      const response = await fetch(nestApiUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          command: "sdm.devices.commands.CameraLiveStream.GenerateWebRtcStream",
          params: { offerSdp: offer.sdp }
        })
      })

      if (!response.ok) {
        const text = await response.text()
        throw new Error(`Nest API failed (${response.status}): ${text}`)
      }

      const { results } = await response.json()
      const mungedSdp = results.answerSdp.replace(/a=sendrecv/g, "a=sendonly")

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          pc.close()
          reject(new Error("Timeout waiting for track"))
        }, trackTimeoutMs)

        const chunks = []
        let recorder = null

        pc.ontrack = (event) => {
          if (event.track.kind === "video" && !recorder) {
            recorder = new MediaRecorder(event.streams[0], {
              mimeType: "video/webm;codecs=vp8,opus"
            })

            recorder.ondataavailable = (e) => {
              if (e.data.size > 0) {
                chunks.push(e.data)
              }
            }

            recorder.onstop = async () => {
              const blob = new Blob(chunks, { type: "video/webm" })
              const buffer = await blob.arrayBuffer()
              resolve(Array.from(new Uint8Array(buffer)))
            }

            recorder.onerror = (e) => {
              reject(new Error(`MediaRecorder error: ${e.error}`))
            }

            recorder.start(1000)
            clearTimeout(timeout)
            setTimeout(() => {
              recorder.stop()
              pc.close()
            }, durationSecs * 1000)
          }
        }

        pc.oniceconnectionstatechange = () => {
          if (pc.iceConnectionState === "failed") {
            clearTimeout(timeout)
            pc.close()
            reject(new Error("ICE connection failed"))
          }
        }

        pc.setRemoteDescription({ type: "answer", sdp: mungedSdp }).catch(reject)
      })
    }, NEST_API_URL, accessToken, parseInt(duration), TRACK_TIMEOUT_MS)

    fs.writeFileSync(outputPath, Buffer.from(chunks))
  } finally {
    await browser.close()
  }
}

record().catch((e) => {
  console.error(e.message)
  process.exit(1)
})
