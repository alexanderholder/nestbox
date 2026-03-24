class Events::RetriesController < ApplicationController
  def create
    @event = Event.find(params[:event_id])
    @event.retry_recording

    redirect_to @event, notice: "Recording retry started"
  end
end
