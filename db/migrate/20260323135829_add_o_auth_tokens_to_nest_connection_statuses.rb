class AddOAuthTokensToNestConnectionStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :nest_connection_statuses, :project_id, :string
    add_column :nest_connection_statuses, :access_token, :text
    add_column :nest_connection_statuses, :refresh_token, :text
    add_column :nest_connection_statuses, :token_expires_at, :datetime
  end
end
