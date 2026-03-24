class AddPubsubModeToNestConnectionStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :nest_connection_statuses, :pubsub_mode, :string, default: "pull", null: false
  end
end
