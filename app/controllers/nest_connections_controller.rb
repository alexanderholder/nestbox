class NestConnectionsController < ApplicationController
  def show
    @connection = NestConnectionStatus.current
  end

  def new
    @connection = NestConnectionStatus.current
    @connection.update!(project_id: nil) if params[:reset]
  end

  def create
    @connection = NestConnectionStatus.current

    if @connection.project_id.blank?
      @connection.update!(project_id: params[:project_id])
    end

    redirect_to @connection.authorize_url(redirect_uri: callback_nest_connection_url), allow_other_host: true
  end

  def callback
    @connection = NestConnectionStatus.current

    if params[:code].present?
      if @connection.exchange_code(code: params[:code], redirect_uri: callback_nest_connection_url)
        sync_cameras
        redirect_to nest_connection_path, notice: "Successfully connected to Nest"
      else
        redirect_to new_nest_connection_path, alert: "Failed to connect: #{@connection.last_error}"
      end
    else
      redirect_to new_nest_connection_path, alert: "Authorization was cancelled or failed"
    end
  end

  def update
    @connection = NestConnectionStatus.current
    @connection.update!(pubsub_mode: params[:pubsub_mode])
    redirect_to nest_connection_path, notice: "Event delivery mode updated"
  end

  def destroy
    NestConnectionStatus.current.disconnect!
    redirect_to nest_connection_path, notice: "Disconnected from Nest"
  end

  private
    def sync_cameras
      Camera.refresh_from_nest
    rescue => e
      Rails.logger.error "Failed to sync cameras after connection: #{e.message}"
    end
end
