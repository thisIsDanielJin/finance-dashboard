# frozen_string_literal: true

class CreateIdealAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :ideal_allocations, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.decimal :percent, precision: 5, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :ideal_allocations, [ :family_id, :category_id ], unique: true
  end
end
