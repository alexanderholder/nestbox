class Event::PollJob < ApplicationJob
  queue_as :default

  def perform
    Event.poll_now
  end
end
