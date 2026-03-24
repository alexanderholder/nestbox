class Event::RecordClipJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(event)
    event.record_clip_now
  end
end
