module Event::Polling
  extend ActiveSupport::Concern

  GCP_PROJECT = ENV["GOOGLE_CLOUD_PROJECT"] || Rails.application.credentials.dig(:google_cloud, :project_id)
  SUBSCRIPTION_NAME = ENV["PUBSUB_SUBSCRIPTION"] || "nestbox-events-sub"

  class_methods do
    def poll_later
      PollJob.perform_later
    end

    def poll_now
      if pubsub_configured?
        Poller.new.process_all
      end
    end

    private
      def pubsub_configured?
        GCP_PROJECT.present?
      end
  end

  class Poller
    def process_all
      total_processed = 0

      loop do
        received_messages = subscriber.pull(immediate: true, max: 100)
        break if received_messages.empty?

        Rails.logger.info "Pulled #{received_messages.size} messages from Pub/Sub"

        received_messages.each do |message|
          process_message(message)
          message.acknowledge!
        end

        total_processed += received_messages.size
      end

      Rails.logger.info "Total processed: #{total_processed} messages"
    rescue Google::Cloud::Error => e
      Rails.logger.error "Pub/Sub poll failed: #{e.message}"
    end

    private
      def subscriber
        @subscriber ||= begin
          require "google/cloud/pubsub"
          Google::Cloud::PubSub.new(project_id: GCP_PROJECT).subscriber(SUBSCRIPTION_NAME)
        end
      end

      def process_message(received_message)
        data = JSON.parse(received_message.data)
        resource_update = data["resourceUpdate"] || {}
        events = resource_update["events"] || {}

        if events.any?
          device_id = extract_device_id(resource_update)
          camera = Camera.find_by(nest_id: device_id)

          if camera
            process_camera_events(camera, events, data)
          else
            Rails.logger.warn "Camera not found for device_id: #{device_id}"
          end
        else
          Rails.logger.debug "No events in message, skipping"
        end
      end

      def extract_device_id(resource_update)
        resource_update["name"]&.split("/")&.last
      end

      def process_camera_events(camera, events, data)
        clip_preview = events["sdm.devices.events.CameraClipPreview.ClipPreview"]
        clip_preview_url = clip_preview&.dig("previewUrl")
        clip_session_id = clip_preview&.dig("eventSessionId")

        has_non_clip_events = events.keys.any? { |k| !k.include?("ClipPreview") }

        if clip_preview_url.present? && clip_session_id.present? && !has_non_clip_events
          update_event_with_clip(camera, clip_session_id, clip_preview_url)
        else
          create_events_from_message(camera, events, data, clip_preview_url)
        end
      end

      def update_event_with_clip(camera, session_id, clip_preview_url)
        event = camera.events.find_by(event_session_id: session_id)

        if event.nil?
          Rails.logger.info "No event found for session_id: #{session_id}, creating placeholder"
        elsif event.clip_preview_url.blank?
          event.update!(clip_preview_url: clip_preview_url)
          event.record_clip_later unless event.completed?
          Rails.logger.info "Updated event #{event.id} with clip URL via session_id"
        end
      end

      def create_events_from_message(camera, events, data, clip_preview_url)
        events.each do |event_type, event_data|
          next if event_type.include?("ClipPreview")

          event_id = event_data["eventId"]
          event_session_id = event_data["eventSessionId"]
          next if event_id.blank?

          create_or_update_event(
            camera: camera,
            event_type: event_type,
            event_id: event_id,
            event_session_id: event_session_id,
            timestamp: data["timestamp"],
            clip_preview_url: clip_preview_url
          )
        end
      end

      def create_or_update_event(camera:, event_type:, event_id:, event_session_id:, timestamp:, clip_preview_url:)
        event = camera.events.find_or_initialize_by(nest_id: event_id)

        if event.persisted?
          update_existing_event(event, event_session_id, clip_preview_url)
        else
          create_new_event(event, event_type, event_session_id, timestamp, clip_preview_url, camera)
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed to create event: #{e.message}"
      end

      def update_existing_event(event, event_session_id, clip_preview_url)
        updates = {}
        updates[:clip_preview_url] = clip_preview_url if clip_preview_url.present? && event.clip_preview_url.blank?
        updates[:event_session_id] = event_session_id if event_session_id.present? && event.event_session_id.blank?

        if updates.any?
          event.update!(updates)
          event.record_clip_later if updates[:clip_preview_url] && !event.completed?
          Rails.logger.info "Updated event #{event.id}"
        end
      end

      def create_new_event(event, event_type, event_session_id, timestamp, clip_preview_url, camera)
        event.event_type = normalize_event_type(event_type)
        event.event_session_id = event_session_id
        event.start_time = Time.parse(timestamp)
        event.end_time = event.start_time + 30.seconds
        event.duration_seconds = 30
        event.clip_preview_url = clip_preview_url
        event.save!

        Rails.logger.info "Created event #{event.id} (#{event.event_type}) for camera #{camera.name}"
        event.record_clip_later if clip_preview_url.present?
      end

      def normalize_event_type(sdm_type)
        case sdm_type
        when /Motion/ then "motion"
        when /Person/ then "person"
        when /Sound/ then "sound"
        when /Chime/, /Doorbell/ then "doorbell"
        else "motion"
        end
      end
  end
end
