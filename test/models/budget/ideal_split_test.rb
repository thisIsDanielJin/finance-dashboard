require "test_helper"

class Budget::IdealSplitTest < ActiveSupport::TestCase
  setup do
    @budget = budgets(:one)
    @budget.sync_budget_categories
    @family = @budget.family
    @food = categories(:food_and_drink)
  end

  test "base uses the budget's expected income" do
    assert_equal 7000.to_d, Budget::IdealSplit.new(@budget).base
  end

  test "configured? only once a positive allocation exists" do
    assert_not Budget::IdealSplit.new(@budget).configured?

    IdealAllocation.create!(family: @family, category: @food, basis: "percent", percent: 20)

    assert Budget::IdealSplit.new(@budget).configured?
  end

  test "rows derive ideal amount from a percent target" do
    IdealAllocation.create!(family: @family, category: @food, basis: "percent", percent: 20)

    row = Budget::IdealSplit.new(@budget).rows.find { |r| r.category == @food }

    assert_equal 20.to_d, row.ideal_percent
    assert_equal 1400.to_d, row.ideal_amount
  end

  test "rows keep a euro target fixed and derive its share" do
    IdealAllocation.create!(family: @family, category: @food, basis: "amount", amount: 1400)

    row = Budget::IdealSplit.new(@budget).rows.find { |r| r.category == @food }

    assert_equal 1400.to_d, row.ideal_amount
    assert_equal 20.to_d, row.ideal_percent
  end

  test "ideal sankey includes income, center and category nodes with links" do
    IdealAllocation.create!(family: @family, category: @food, basis: "amount", amount: 1400)

    data = Budget::IdealSplit.new(@budget).sankey(:ideal)

    assert_equal "ideal", data[:mode]
    assert data[:nodes].any? { |node| node[:id] == "ideal_income" }
    assert data[:nodes].any? { |node| node[:id] == "ideal_center" }
    assert data[:links].present?
  end

  test "row reports deviation and over_ideal state" do
    over = Budget::IdealSplit::Row.new(
      category: @food, ideal_percent: 10.to_d, ideal_amount: 100.to_d,
      budgeted_amount: 120.to_d, actual_amount: 150.to_d
    )
    under = Budget::IdealSplit::Row.new(
      category: @food, ideal_percent: 10.to_d, ideal_amount: 100.to_d,
      budgeted_amount: 80.to_d, actual_amount: 60.to_d
    )

    assert_equal 50.to_d, over.deviation
    assert over.over_ideal?
    assert_not under.over_ideal?
  end
end
