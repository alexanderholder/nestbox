class Cameras::SyncsController < ApplicationController
  include CameraScoped

  def create
    @camera.sync_later
    redirect_to @camera, notice: "Sync started"
  end
end
