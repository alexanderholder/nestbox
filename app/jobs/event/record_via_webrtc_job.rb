class Event::RecordViaWebrtcJob < ApplicationJob
  queue_as :recordings

  discard_on ActiveJob::DeserializationError

  def perform(event)
    event.record_via_webrtc_now
  end
end
