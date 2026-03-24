class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  stale_when_importmap_changes

  private
    def nest_connection_status
      @nest_connection_status ||= NestConnectionStatus.current
    end
    helper_method :nest_connection_status
end
