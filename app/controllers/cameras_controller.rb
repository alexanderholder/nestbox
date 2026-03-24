class CamerasController < ApplicationController
  def index
    @cameras = Camera.ordered
  end

  def show
    @camera = Camera.find(params[:id])
    @events = @camera.events.reverse_chronologically.limit(50)
  end
end
