class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :camera, null: false, foreign_key: true
      t.string :nest_id, null: false
      t.string :event_type, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time
      t.integer :duration_seconds
      t.string :clip_url
      t.string :download_state, default: "pending"
      t.datetime :downloaded_at

      t.timestamps
    end
    add_index :events, :nest_id, unique: true
    add_index :events, [ :camera_id, :start_time ]
    add_index :events, :download_state
  end
end
