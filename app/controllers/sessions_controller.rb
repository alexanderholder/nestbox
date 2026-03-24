class SessionsController < ApplicationController
  allow_unauthenticated_access

  layout "session"

  def new
  end

  def create
    if authenticate(params[:password])
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end
