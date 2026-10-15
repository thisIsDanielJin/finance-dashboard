# An "ideal" target for one root (top-level) category, used by the budget page's
# Ideal Split Sankey to compare how the user *wants* their money to flow against
# how it was budgeted and actually spent.
#
# Each target is entered in one of two units (`basis`): a fixed euro `amount`,
# or a `percent` of the budget's expected income. Euro targets are
# income-independent; percent targets scale with the month's expected income.
# Family-wide (no user_id): a single standing target for the household,
# independent of any one month's budget.
class IdealAllocation < ApplicationRecord
  BASES = %w[percent amount].freeze

  belongs_to :family
  belongs_to :category

  validates :basis, inclusion: { in: BASES }
  validates :percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :percent, presence: true, if: -> { basis == "percent" }
  validates :amount, presence: true, if: -> { basis == "amount" }
  validates :category_id, uniqueness: { scope: :family_id }

  # The ideal euro amount, given a `base` income to resolve percent targets.
  def ideal_amount(base)
    basis == "amount" ? amount.to_d : (percent.to_d / 100 * base.to_d)
  end

  # The ideal share of income, given a `base` income to resolve euro targets.
  def ideal_percent(base)
    return percent.to_d if basis == "percent"
    base.to_d.zero? ? 0.to_d : (amount.to_d / base.to_d * 100)
  end

  # The number the user actually typed, in whichever unit they chose.
  def entered_value
    basis == "amount" ? amount.to_d : percent.to_d
  end
end
