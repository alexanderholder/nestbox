class CreateNestConnectionStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :nest_connection_statuses do |t|
      t.string :state, null: false, default: "unknown"
      t.text :last_error
      t.datetime :last_success_at
      t.datetime :last_failure_at

      t.timestamps
    end
  end
end
