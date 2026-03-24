class Event < ApplicationRecord
  include Downloadable, Polling

  belongs_to :camera

  validates :nest_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :start_time, presence: true

  scope :chronologically, -> { order(start_time: :asc) }
  scope :reverse_chronologically, -> { order(start_time: :desc) }
  scope :pending_download, -> { where(download_state: "pending") }
  scope :downloaded, -> { where(download_state: "completed") }
  scope :failed_download, -> { where(download_state: "failed") }
  scope :on_date, ->(date) { where(start_time: date.all_day) }

  enum :download_state, {
    pending: "pending",
    downloading: "downloading",
    completed: "completed",
    failed: "failed"
  }, default: :pending
end
