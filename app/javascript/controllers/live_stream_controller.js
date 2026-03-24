import { Controller } from "@hotwired/stimulus"
import { patch, post } from "@rails/request.js"

export default class extends Controller {
  static targets = [ "video", "status", "reconnectButton", "startButton", "stopButton" ]
  static values = { cameraId: Number, autoConnect: { type: Boolean, default: true } }
  static classes = [ "connecting", "live", "error", "disconnected" ]

  connect() {
    if (this.autoConnectValue) {
      this.#startStream()
    }
  }

  disconnect() {
    this.#stopStream()
  }

  reconnect() {
    this.#stopStream()
    this.#startStream()
  }

  stop() {
    this.#stopStream()
    this.#setStatus("disconnected", "Not connected")
    this.#showStartButton()
  }

  async #startStream() {
    this.#setStatus("connecting", "Connecting...")
    this.#hideReconnectButton()
    this.#hideStartButton()

    try {
      this.peerConnection = new RTCPeerConnection({
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
      })

      this.peerConnection.ontrack = this.#handleTrack
      this.peerConnection.oniceconnectionstatechange = this.#handleIceConnectionStateChange

      this.peerConnection.addTransceiver("audio", { direction: "recvonly" })
      this.peerConnection.addTransceiver("video", { direction: "recvonly" })
      this.dataChannel = this.peerConnection.createDataChannel("dataSendChannel")

      const offer = await this.peerConnection.createOffer()
      await this.peerConnection.setLocalDescription(offer)

      const response = await this.#exchangeOffer(offer.sdp)

      if (response.ok) {
        const { answer_sdp, session_id } = await response.json
        this.sessionId = session_id

        const mungedSdp = this.#mungeAnswerSdp(answer_sdp)

        await this.peerConnection.setRemoteDescription({
          type: "answer",
          sdp: mungedSdp
        })

        this.#scheduleExtension()
      } else {
        this.#handleError("Failed to connect to camera")
      }
    } catch (error) {
      this.#handleError("Connection error")
    }
  }

  #handleTrack = (event) => {
    this.videoTarget.srcObject = event.streams[0]
    this.#setStatus("live", "Live")
  }

  #handleIceConnectionStateChange = () => {
    const state = this.peerConnection.iceConnectionState

    switch (state) {
      case "connected":
      case "completed":
        this.#setStatus("live", "Live")
        break
      case "disconnected":
        this.#setStatus("disconnected", "Disconnected")
        this.#showReconnectButton()
        break
      case "failed":
        this.#handleError("Connection failed")
        break
      case "checking":
        this.#setStatus("connecting", "Connecting...")
        break
    }
  }

  #handleError(message) {
    this.#setStatus("error", message)
    this.#showReconnectButton()
    this.#showStartButton()
    this.#stopStream()
  }

  async #exchangeOffer(offerSdp) {
    return post(`/cameras/${this.cameraIdValue}/stream`, {
      body: JSON.stringify({ offer_sdp: offerSdp }),
      contentType: "application/json"
    })
  }

  #scheduleExtension() {
    this.extensionTimer = setInterval(async () => {
      try {
        await patch(`/cameras/${this.cameraIdValue}/stream`, {
          body: JSON.stringify({ session_id: this.sessionId }),
          contentType: "application/json"
        })
      } catch {
        this.#handleError("Stream expired")
      }
    }, 4 * 60 * 1000)
  }

  #stopStream() {
    if (this.extensionTimer) {
      clearInterval(this.extensionTimer)
      this.extensionTimer = null
    }

    if (this.peerConnection) {
      this.peerConnection.close()
      this.peerConnection = null
    }
  }

  #setStatus(state, message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.className = `status status--${state}`
    }

    this.element.dataset.streamState = state
  }

  #showReconnectButton() {
    if (this.hasReconnectButtonTarget) {
      this.reconnectButtonTarget.hidden = false
    }
  }

  #hideReconnectButton() {
    if (this.hasReconnectButtonTarget) {
      this.reconnectButtonTarget.hidden = true
    }
  }

  #showStartButton() {
    if (this.hasStartButtonTarget) {
      this.startButtonTarget.hidden = false
    }
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.hidden = true
    }
  }

  #hideStartButton() {
    if (this.hasStartButtonTarget) {
      this.startButtonTarget.hidden = true
    }
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.hidden = false
    }
  }

  #mungeAnswerSdp(sdp) {
    return sdp.replace(/a=sendrecv/g, "a=sendonly")
  }
}
