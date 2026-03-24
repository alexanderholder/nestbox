module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      session[:authenticated] == true
    end

    def require_authentication
      redirect_to new_session_path unless authenticated?
    end

    def authenticate(password)
      if password.present? && valid_password?(password)
        session[:authenticated] = true
      end
    end

    def valid_password?(password)
      stored = Rails.application.credentials.password
      stored.present? && ActiveSupport::SecurityUtils.secure_compare(password, stored)
    end

    def terminate_session
      session.delete(:authenticated)
    end
end
