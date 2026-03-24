module Event::Downloadable
  extend ActiveSupport::Concern
  include SslConfigurable

  included do
    has_one_attached :clip
    has_one_attached :webrtc_clip

    after_create_commit :record_clip_later, if: :recordable?
  end

  class_methods do
    def retry_failed
      failed_download.find_each(&:retry_recording)
    end

    def recover_stale(threshold: 5.minutes.ago)
      where(download_state: :downloading)
        .where("updated_at < ?", threshold)
        .find_each(&:retry_recording)
    end
  end

  def record_clip_later
    Event::RecordClipJob.perform_later(self)
  end

  def record_clip_now
    return if completed? || !recordable?

    downloading!

    record_via_webrtc_now

    download_clip_preview if clip_preview_url.present? && !clip.attached?
  end

  def retry_recording
    update!(download_state: :pending)
    record_clip_later
  end

  def recordable?
    camera.present?
  end

  def has_clip?
    webrtc_clip.attached? || clip.attached?
  end

  def preferred_clip
    if webrtc_clip.attached?
      webrtc_clip
    elsif clip.attached?
      clip
    end
  end

  private
    def download_clip_preview
      access_token = NestConnectionStatus.current.current_access_token

      uri = URI(clip_preview_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert_store = build_cert_store

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"

      response = http.request(request)

      if response.code.to_i == 200
        clip.attach(
          io: StringIO.new(response.body),
          filename: "#{id}_preview.mp4",
          content_type: response.content_type || "video/mp4"
        )
      end
    rescue => e
      Rails.logger.error "Clip preview download failed: #{e.message}"
    end
end
