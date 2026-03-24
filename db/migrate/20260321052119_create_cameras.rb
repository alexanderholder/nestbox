class CreateCameras < ActiveRecord::Migration[8.1]
  def change
    create_table :cameras do |t|
      t.string :nest_id, null: false
      t.string :name, null: false
      t.string :device_type
      t.datetime :last_synced_at

      t.timestamps
    end
    add_index :cameras, :nest_id, unique: true
  end
end
