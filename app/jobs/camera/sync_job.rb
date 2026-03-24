class Camera::SyncJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(camera)
    camera.sync_now
  end
end
