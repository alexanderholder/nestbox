module Event::Polling
  extend ActiveSupport::Concern

  GCP_PROJECT = ENV["GOOGLE_CLOUD_PROJECT"] || Rails.application.credentials.dig(:google_cloud, :project_id)
  SUBSCRIPTION_NAME = ENV["PUBSUB_SUBSCRIPTION"] || "nestbox-events-sub"

  class_methods do
    def poll_later
      Event::PollJob.perform_later
    end

    def poll_now
      return unless should_poll?

      Poller.new.process_all
    end

    private
      def should_poll?
        GCP_PROJECT.present? && NestConnectionStatus.current&.pull?
      end
  end

  class Poller
    def process_all
      total_processed = 0

      loop do
        received_messages = subscriber.pull(immediate: true, max: 100)
        break if received_messages.empty?

        received_messages.each do |message|
          process_message(message)
          message.acknowledge!
        end

        total_processed += received_messages.size
      end

      Rails.logger.info "Processed #{total_processed} Pub/Sub messages" if total_processed > 0
    rescue Google::Cloud::Error => e
      Rails.logger.error "Pub/Sub poll failed: #{e.message}"
    end

    def process_message(received_message)
      data = JSON.parse(received_message.data)
      resource_update = data["resourceUpdate"] || {}
      events = resource_update["events"] || {}

      return if events.empty?

      device_id = extract_device_id(resource_update)
      camera = Camera.find_by(nest_id: device_id)

      if camera
        process_camera_events(camera, events, data)
      else
        Rails.logger.warn "Unknown camera: #{device_id}"
      end
    end

    private
      def subscriber
        @subscriber ||= begin
          require "google/cloud/pubsub"
          Google::Cloud::PubSub.new(project_id: GCP_PROJECT).subscriber(SUBSCRIPTION_NAME)
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

        if event && event.clip_preview_url.blank?
          event.update!(clip_preview_url: clip_preview_url)
          event.record_clip_later unless event.completed?
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
        end
      end

      def create_new_event(event, event_type, event_session_id, timestamp, clip_preview_url, camera)
        event.assign_attributes(
          event_type: normalize_event_type(event_type),
          event_session_id: event_session_id,
          start_time: Time.parse(timestamp),
          end_time: Time.parse(timestamp) + 30.seconds,
          duration_seconds: 30,
          clip_preview_url: clip_preview_url
        )
        event.save!

        Rails.logger.info "Event created: #{camera.name} #{event.event_type}"
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
