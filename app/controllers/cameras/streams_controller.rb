class Cameras::StreamsController < ApplicationController
  include CameraScoped

  def show
  end

  def create
    result = generate_stream

    render json: {
      answer_sdp: result["answerSdp"],
      session_id: result["mediaSessionId"]
    }
  end

  def update
    result = extend_stream
    render json: { expires_at: result&.dig("expiresAt") }
  end

  private
    def generate_stream
      nest_connection.generate_webrtc_stream(
        device_id: @camera.nest_id,
        offer_sdp: params[:offer_sdp]
      )
    end

    def extend_stream
      nest_connection.extend_webrtc_stream(
        device_id: @camera.nest_id,
        session_id: params[:session_id]
      )
    end

    def nest_connection
      @nest_connection ||= NestConnectionStatus.current
    end
end
