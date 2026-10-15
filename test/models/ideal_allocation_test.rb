require "test_helper"

class IdealAllocationTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @category = categories(:food_and_drink)
  end

  test "valid with percent within range" do
    assert IdealAllocation.new(family: @family, category: @category, basis: "percent", percent: 25).valid?
  end

  test "rejects percent above 100" do
    assert_not IdealAllocation.new(family: @family, category: @category, basis: "percent", percent: 150).valid?
  end

  test "rejects negative percent" do
    assert_not IdealAllocation.new(family: @family, category: @category, basis: "percent", percent: -1).valid?
  end

  test "amount basis requires an amount" do
    allocation = IdealAllocation.new(family: @family, category: @category, basis: "amount")
    assert_not allocation.valid?

    allocation.amount = 500
    assert allocation.valid?
  end

  test "rejects negative amount" do
    assert_not IdealAllocation.new(family: @family, category: @category, basis: "amount", amount: -1).valid?
  end

  test "is unique per family and category" do
    IdealAllocation.create!(family: @family, category: @category, basis: "percent", percent: 10)
    assert_not IdealAllocation.new(family: @family, category: @category, basis: "percent", percent: 20).valid?
  end

  test "ideal_amount resolves a percent target against the base" do
    allocation = IdealAllocation.new(basis: "percent", percent: 10)
    assert_equal 700.to_d, allocation.ideal_amount(7000)
  end

  test "ideal_amount keeps a euro target fixed regardless of base" do
    allocation = IdealAllocation.new(basis: "amount", amount: 500)
    assert_equal 500.to_d, allocation.ideal_amount(7000)
    assert_equal 500.to_d, allocation.ideal_amount(0)
  end

  test "ideal_percent derives a share from a euro target and the base" do
    allocation = IdealAllocation.new(basis: "amount", amount: 700)
    assert_equal 10.to_d, allocation.ideal_percent(7000)
    assert_equal 0.to_d, allocation.ideal_percent(0)
  end
end
