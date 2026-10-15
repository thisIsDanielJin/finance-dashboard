# frozen_string_literal: true

class AddAmountAndBasisToIdealAllocations < ActiveRecord::Migration[8.1]
  def change
    add_column :ideal_allocations, :amount, :decimal, precision: 12, scale: 2
    add_column :ideal_allocations, :basis, :string, null: false, default: "percent"
    change_column_null :ideal_allocations, :percent, true
  end
end
