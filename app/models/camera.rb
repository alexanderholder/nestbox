class Camera < ApplicationRecord
  include Syncable

  has_many :events, dependent: :destroy

  validates :nest_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :ordered, -> { order(name: :asc) }
end
