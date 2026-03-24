class NestConnectionStatus < ApplicationRecord
  include SslConfigurable

  class AuthenticationError < StandardError; end
  class ApiError < StandardError; end

  OAUTH_AUTHORIZE_URL = "https://nestservices.google.com/partnerconnections".freeze
  OAUTH_TOKEN_URL = "https://www.googleapis.com/oauth2/v4/token".freeze
  OAUTH_SCOPE = "https://www.googleapis.com/auth/sdm.service".freeze
  SDM_API_URL = "https://smartdevicemanagement.googleapis.com/v1".freeze

  validates :state, presence: true

  enum :state, {
    unknown: "unknown",
    connected: "connected",
    disconnected: "disconnected",
    auth_failed: "auth_failed"
  }, default: :unknown

  enum :pubsub_mode, { pull: "pull", push: "push" }, default: :pull

  def self.current
    first_or_create!
  end

  def configured?
    project_id.present? && refresh_token.present?
  end

  def healthy?
    connected? && configured?
  end

  def authorize_url(redirect_uri:)
    params = {
      redirect_uri: redirect_uri,
      access_type: "offline",
      prompt: "consent",
      client_id: client_id,
      response_type: "code",
      scope: OAUTH_SCOPE
    }

    "#{OAUTH_AUTHORIZE_URL}/#{project_id}/auth?#{params.to_query}"
  end

  def exchange_code(code:, redirect_uri:)
    response = token_request(
      code: code,
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    )

    if response["refresh_token"]
      update!(
        refresh_token: response["refresh_token"],
        access_token: response["access_token"],
        token_expires_at: Time.current + response["expires_in"].to_i.seconds,
        state: :connected,
        last_success_at: Time.current,
        last_error: nil
      )
      true
    else
      update!(state: :auth_failed, last_error: response["error_description"] || response["error"])
      false
    end
  end

  def refresh_access_token!
    return unless refresh_token

    response = token_request(
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    )

    if response["access_token"]
      update!(
        access_token: response["access_token"],
        token_expires_at: Time.current + response["expires_in"].to_i.seconds
      )
      access_token
    else
      update!(state: :auth_failed, last_error: response["error_description"] || response["error"])
      nil
    end
  end

  def current_access_token
    if token_expired?
      refresh_access_token!
    else
      access_token
    end
  end

  def token_expired?
    access_token.blank? || token_expires_at.blank? || Time.current >= token_expires_at
  end

  def disconnect!
    update!(
      access_token: nil,
      refresh_token: nil,
      token_expires_at: nil,
      state: :disconnected
    )
  end

  def record_success
    update!(
      state: :connected,
      last_success_at: Time.current,
      last_error: nil
    )
  end

  def record_failure(error)
    update!(
      state: :disconnected,
      last_failure_at: Time.current,
      last_error: error.message
    )
  end

  def record_auth_failure(error)
    update!(
      state: :auth_failed,
      last_failure_at: Time.current,
      last_error: error.message
    )
  end

  def fetch_cameras
    fetch_devices.select { |d| d[:camera] }
  end

  def generate_webrtc_stream(device_id:, offer_sdp:)
    response = execute_command(device_id, "CameraLiveStream.GenerateWebRtcStream", offerSdp: offer_sdp)
    response["results"]
  end

  def extend_webrtc_stream(device_id:, session_id:)
    response = execute_command(device_id, "CameraLiveStream.ExtendWebRtcStream", mediaSessionId: session_id)
    response["results"]
  end

  def test_api_connection
    fetch_cameras
    true
  rescue => e
    raise AuthenticationError, "Connection test failed: #{e.message}"
  end

  private
    def token_request(params)
      uri = URI(OAUTH_TOKEN_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert_store = build_cert_store

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(
        { client_id: client_id, client_secret: client_secret }.merge(params)
      )

      response = http.request(request)
      JSON.parse(response.body)
    end

    def client_id
      Rails.application.credentials.dig(:nest, :client_id)
    end

    def client_secret
      Rails.application.credentials.dig(:nest, :client_secret)
    end

    def fetch_devices
      validate_api_connection!

      response = api_get("/enterprises/#{project_id}/devices")
      devices = response["devices"] || []

      devices.map { |data| parse_device(data) }
    end

    def parse_device(data)
      traits = data["traits"]&.keys || []
      type = data["type"] || ""

      {
        id: data["name"]&.split("/")&.last,
        name: data.dig("traits", "sdm.devices.traits.Info", "customName") ||
              data.dig("parentRelations", 0, "displayName") ||
              "Unknown Device",
        device_type: determine_device_type(type, traits),
        camera: camera_device?(traits)
      }
    end

    def determine_device_type(type, traits)
      if type.include?("DOORBELL") || traits.any? { |t| t.include?("DoorbellChime") }
        "doorbell"
      elsif traits.any? { |t| t.include?("CameraLiveStream") || t.include?("CameraImage") }
        "camera"
      elsif traits.any? { |t| t.include?("ThermostatTemperatureSetpoint") }
        "thermostat"
      else
        "unknown"
      end
    end

    def camera_device?(traits)
      traits.any? { |t| t.include?("CameraLiveStream") || t.include?("CameraImage") }
    end

    def execute_command(device_id, command, params)
      validate_api_connection!

      api_post(
        "/enterprises/#{project_id}/devices/#{device_id}:executeCommand",
        { command: "sdm.devices.commands.#{command}", params: params }
      )
    end

    def validate_api_connection!
      raise AuthenticationError, "Nest connection not configured" unless configured?
    end

    def api_get(path)
      uri = URI("#{SDM_API_URL}#{path}")

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{api_access_token}"
      request["Content-Type"] = "application/json"

      execute_api_request(uri, request)
    end

    def api_post(path, body)
      uri = URI("#{SDM_API_URL}#{path}")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_access_token}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      execute_api_request(uri, request)
    end

    def execute_api_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert_store = build_cert_store
      http.open_timeout = 30
      http.read_timeout = 60

      response = http.request(request)

      case response.code.to_i
      when 200..299
        JSON.parse(response.body)
      when 401
        record_auth_failure(AuthenticationError.new("Token expired"))
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 403
        raise AuthenticationError, "Access denied: #{response.body}"
      else
        raise ApiError, "API request failed (#{response.code}): #{response.body}"
      end
    end

    def api_access_token
      current_access_token || raise(AuthenticationError, "Failed to get access token")
    end
end
