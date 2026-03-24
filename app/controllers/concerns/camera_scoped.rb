module CameraScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_camera
  end

  private
    def set_camera
      @camera = Camera.find(params[:camera_id])
    end
end
