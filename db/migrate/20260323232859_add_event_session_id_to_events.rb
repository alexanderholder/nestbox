class AddEventSessionIdToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :event_session_id, :string
    add_index :events, :event_session_id
  end
end
