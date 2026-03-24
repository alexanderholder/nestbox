module Event::Downloadable
  extend ActiveSupport::Concern
  include SslConfigurable

  CLIP_DURATION_SECONDS = 10

  included do
    has_one_attached :image
    has_one_attached :clip

    after_create_commit :record_clip_later, if: :recordable?
  end

  class_methods do
    def record_all_pending
      pending_download.find_each(&:record_clip_later)
    end

    def retry_all_failed
      failed_download.where.not(clip_preview_url: nil).find_each(&:retry_recording)
    end

    def retry_all_with_urls
      where(download_state: [ :failed, :pending ])
        .where.not(clip_preview_url: nil)
        .find_each(&:retry_recording)
    end

    def recover_stale_downloads(threshold: 5.minutes.ago)
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

    if clip_preview_url.present?
      download_and_attach_clip(clip_preview_url)
      update!(download_state: :completed, downloaded_at: Time.current)
    else
      update!(download_state: :failed)
      Rails.logger.info "No clip preview URL for event #{id}"
    end
  rescue NestConnectionStatus::AuthenticationError => e
    NestConnectionStatus.current.record_auth_failure(e)
    update!(download_state: :failed)
    raise
  rescue NestConnectionStatus::ApiError => e
    update!(download_state: :failed)
    Rails.logger.error "Clip download failed: #{e.message}"
  rescue => e
    update!(download_state: :failed)
    Rails.logger.error "Failed to download clip: #{e.class}: #{e.message}"
  end

  def retry_recording
    update!(download_state: :pending)
    record_clip_later
  end

  def recordable?
    camera.present?
  end

  private
    def download_and_attach_clip(url)
      access_token = NestConnectionStatus.current.current_access_token

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert_store = build_cert_store

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"

      response = http.request(request)

      if response.code.to_i == 200
        clip.attach(
          io: StringIO.new(response.body),
          filename: "#{id}.mp4",
          content_type: response.content_type || "video/mp4"
        )
      else
        raise NestConnectionStatus::ApiError, "Failed to download clip: #{response.code}"
      end
    end
end
