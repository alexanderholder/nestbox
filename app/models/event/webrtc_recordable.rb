module Event::WebrtcRecordable
  extend ActiveSupport::Concern

  WEBRTC_DURATION_SECONDS = 20
  WEBRTC_MAX_RETRIES = 5
  WEBRTC_RETRY_DELAY = 3

  def record_via_webrtc_later
    Event::RecordViaWebrtcJob.perform_later(self)
  end

  def record_via_webrtc_now
    return if webrtc_clip.attached?

    supplementary = completed?
    downloading! unless supplementary

    result = execute_webrtc_recording

    if result[:success]
      attach_webrtc_recording(result[:file_path])
      mark_completed unless supplementary
    else
      mark_failed(result[:error]) unless supplementary
    end
  ensure
    FileUtils.rm_f(result[:file_path]) if result&.dig(:file_path)
  end

  private
    def execute_webrtc_recording
      FileUtils.mkdir_p(recordings_tmp_dir)
      output_path = recordings_tmp_path

      WEBRTC_MAX_RETRIES.times do |attempt|
        connection = NestConnectionStatus.current

        success = system(
          "node", webrtc_script_path,
          camera.nest_id,
          WEBRTC_DURATION_SECONDS.to_s,
          output_path,
          connection.current_access_token,
          connection.project_id
        )

        if success && File.exist?(output_path)
          return { success: true, file_path: convert_to_mp4(output_path) }
        end

        sleep(WEBRTC_RETRY_DELAY * (attempt + 1)) if attempt < WEBRTC_MAX_RETRIES - 1
      end

      { success: false, error: "Recording failed after #{WEBRTC_MAX_RETRIES} attempts" }
    end

    def recordings_tmp_dir
      Rails.root.join("tmp", "recordings")
    end

    def recordings_tmp_path
      recordings_tmp_dir.join("#{SecureRandom.uuid}.webm").to_s
    end

    def webrtc_script_path
      Rails.root.join("script", "webrtc", "recorder.js").to_s
    end

    def convert_to_mp4(webm_path)
      mp4_path = webm_path.sub(".webm", ".mp4")
      system("ffmpeg", "-y", "-i", webm_path, "-c:v", "libx264", "-preset", "fast", mp4_path)
      FileUtils.rm_f(webm_path)
      mp4_path
    end

    def attach_webrtc_recording(file_path)
      webrtc_clip.attach(
        io: File.open(file_path),
        filename: "#{id}_webrtc.mp4",
        content_type: "video/mp4"
      )
    end

    def mark_completed
      update!(download_state: :completed, downloaded_at: Time.current)
    end

    def mark_failed(error)
      update!(download_state: :failed)
      Rails.logger.error "WebRTC recording failed for event #{id}: #{error}"
    end
end
