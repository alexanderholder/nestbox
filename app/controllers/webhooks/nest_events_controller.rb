class Webhooks::NestEventsController < ActionController::Base
  skip_before_action :verify_authenticity_token

  def create
    message = extract_pubsub_message
    Event::Polling::Poller.new.process_message(message) if message
    head :ok
  end

  private
    def extract_pubsub_message
      data = params.dig(:message, :data)
      return nil unless data

      Struct.new(:data).new(Base64.decode64(data))
    end
end
