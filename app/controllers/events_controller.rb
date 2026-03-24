class EventsController < ApplicationController
  def index
    @events = Event.includes(:camera)
                   .reverse_chronologically

    @events = @events.where(camera_id: params[:camera_id]) if params[:camera_id].present?
    @events = @events.on_date(date_param) if params[:date].present?
    @events = @events.limit(100)
  end

  def show
    @event = Event.find(params[:id])
    @previous_event = @event.camera.events.where("start_time < ?", @event.start_time).reverse_chronologically.first
    @next_event = @event.camera.events.where("start_time > ?", @event.start_time).chronologically.first
  end

  private
    def date_param
      Date.parse(params[:date])
    rescue ArgumentError
      Date.current
    end
end
