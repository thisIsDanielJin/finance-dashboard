require "test_helper"

class IdealAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
    @family = @user.family
    @food = categories(:food_and_drink)
    @budget_param = Budget.date_to_param(Date.current)
  end

  test "edit renders the ideal split form" do
    get edit_ideal_allocations_url

    assert_response :success
  end

  test "update stores a euro amount target and redirects to the budget" do
    assert_difference -> { @family.ideal_allocations.count }, 1 do
      patch ideal_allocations_url, params: {
        basis: "amount",
        values: { @food.id => "1200" },
        return_to: budget_path(@budget_param)
      }
    end

    assert_redirected_to budget_path(@budget_param)
    allocation = @family.ideal_allocations.find_by(category: @food)
    assert_equal "amount", allocation.basis
    assert_equal 1200.to_d, allocation.amount
    assert_nil allocation.percent
  end

  test "update stores a percent target" do
    patch ideal_allocations_url, params: { basis: "percent", values: { @food.id => "30" } }

    allocation = @family.ideal_allocations.find_by(category: @food)
    assert_equal "percent", allocation.basis
    assert_equal 30.to_d, allocation.percent
    assert_nil allocation.amount
  end

  test "update removes a target set to zero" do
    IdealAllocation.create!(family: @family, category: @food, basis: "amount", amount: 100)

    assert_difference -> { @family.ideal_allocations.count }, -1 do
      patch ideal_allocations_url, params: { basis: "amount", values: { @food.id => "0" } }
    end
  end

  test "update ignores an off-site return_to" do
    patch ideal_allocations_url, params: {
      basis: "amount",
      values: { @food.id => "10" },
      return_to: "https://evil.example.com"
    }

    assert_redirected_to budgets_path
  end

  test "update with an out-of-range percent is rejected" do
    patch ideal_allocations_url, params: { basis: "percent", values: { @food.id => "150" } }

    assert_redirected_to edit_ideal_allocations_path
    assert_equal 0, @family.ideal_allocations.count
  end

  test "budget page renders the ideal split section once configured" do
    IdealAllocation.create!(family: @family, category: @food, basis: "amount", amount: 1400)

    get budget_url(@budget_param)

    assert_response :success
    assert_select "h2", text: I18n.t("budgets.ideal_split.title")
  end
end
