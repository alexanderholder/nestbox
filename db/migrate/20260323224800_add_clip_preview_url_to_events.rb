class AddClipPreviewUrlToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :clip_preview_url, :text
  end
end
