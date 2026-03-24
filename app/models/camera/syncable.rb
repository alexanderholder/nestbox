module Camera::Syncable
  extend ActiveSupport::Concern

  included do
    scope :due_for_sync, -> { where("last_synced_at IS NULL OR last_synced_at < ?", 5.minutes.ago) }
  end

  class_methods do
    def sync_all_now
      find_each(&:sync_now)
    end

    def sync_all_later
      find_each(&:sync_later)
    end

    def refresh_from_nest
      connection = NestConnectionStatus.current
      devices = connection.fetch_cameras

      devices.each do |device|
        camera = find_or_initialize_by(nest_id: device[:id])
        camera.update!(
          name: device[:name],
          device_type: device[:device_type]
        )
      end

      connection.record_success
      where(nest_id: devices.map { |d| d[:id] })
    rescue NestConnectionStatus::Api::AuthenticationError => e
      NestConnectionStatus.current.record_auth_failure(e)
      raise
    rescue NestConnectionStatus::Api::ApiError => e
      NestConnectionStatus.current.record_failure(e)
      raise
    end
  end

  def sync_later
    SyncJob.perform_later(self)
  end

  def sync_now
    connection = NestConnectionStatus.current
    device = connection.fetch_cameras.find { |d| d[:id] == nest_id }

    if device
      update!(name: device[:name], device_type: device[:device_type])
    end

    touch(:last_synced_at)
    connection.record_success
  rescue NestConnectionStatus::Api::AuthenticationError => e
    NestConnectionStatus.current.record_auth_failure(e)
    raise
  rescue NestConnectionStatus::Api::ApiError => e
    NestConnectionStatus.current.record_failure(e)
    raise
  end
end
