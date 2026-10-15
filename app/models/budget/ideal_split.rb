# Compares, for one month's budget, how the family *wants* income to split
# across top-level categories (the family-wide IdealAllocation targets) against
# how it was budgeted and how it was actually spent. Produces both a per-category
# comparison (`rows`) and Sankey diagrams (`sankey(:ideal|:budgeted|:actual)`) in
# the same node/link shape as IncomeStatement::Sankey, so the existing
# `sankey-chart` Stimulus controller renders them unchanged.
#
# Percentages are of the budget's expected income (falling back to actual income
# when none is set). In the ideal diagram, each category flow is colored by
# deviation: destructive when actual spend exceeds the ideal amount, success
# when it is at or under target.
class Budget::IdealSplit
  Row = Data.define(:category, :ideal_percent, :ideal_amount, :budgeted_amount, :actual_amount) do
    def deviation
      actual_amount - ideal_amount
    end

    def over_ideal?
      deviation.positive?
    end

    def actual_percent_of_ideal
      return 0 if ideal_amount.zero?
      (actual_amount / ideal_amount.to_f * 100).round(1)
    end
  end

  SUCCESS_COLOR = "var(--color-success)"
  DESTRUCTIVE_COLOR = "var(--color-destructive)"
  REMAINDER_COLOR = "var(--color-gray-400)"

  def initialize(budget)
    @budget = budget
    @family = budget.family
  end

  def base
    @base ||= begin
      income = @budget.expected_income.to_d
      income = @budget.actual_income.to_d if income.zero?
      [ income, 0 ].max
    end
  end

  def currency
    @family.currency
  end

  # Whether the family has set up any ideal targets at all.
  def configured?
    allocations_by_category_id.values.any? { |allocation| allocation.entered_value.positive? }
  end

  def total_ideal_percent
    allocations_by_category_id.values.sum { |allocation| allocation.ideal_percent(base) }
  end

  def rows
    @rows ||= root_budget_categories.map do |budget_category|
      category = budget_category.category
      allocation = allocations_by_category_id[category.id]
      Row.new(
        category: category,
        ideal_percent: allocation ? allocation.ideal_percent(base) : 0.to_d,
        ideal_amount: allocation ? allocation.ideal_amount(base).round(2) : 0.to_d,
        budgeted_amount: budget_category.budgeted_spending.to_d,
        actual_amount: @budget.budget_category_actual_spending(budget_category).to_d
      )
    end.sort_by { |row| [ -row.ideal_amount, -row.actual_amount ] }
  end

  def sankey(mode)
    nodes = []
    links = []
    pool = source_value(mode)

    return empty_sankey if pool.zero?

    income_index = add_node(nodes, id: "ideal_income", name: I18n.t("budgets.ideal_split.income_node"),
                                   kind: :income, value: pool, percentage: 100)
    center_index = add_node(nodes, id: "ideal_center", name: I18n.t("budgets.ideal_split.center_node"),
                                   kind: :cash_flow, value: pool, percentage: 100)
    add_link(links, income_index, center_index, pool, 100)

    allocated = 0.to_d
    rows.each do |row|
      amount = amount_for(row, mode)
      next unless amount.positive?

      allocated += amount
      node_index = add_node(nodes,
        id: "ideal_#{mode}_#{row.category.id}",
        name: row.category.name,
        kind: :expense,
        value: amount,
        percentage: percentage(amount, pool),
        category: row.category,
        color: node_color(row, mode)
      )
      add_link(links, center_index, node_index, amount, percentage(amount, pool))
    end

    remainder = (pool - allocated).round(2)
    if remainder.positive?
      node_index = add_node(nodes, id: "ideal_#{mode}_remainder",
        name: I18n.t("budgets.ideal_split.unallocated_node"),
        kind: :surplus, value: remainder, percentage: percentage(remainder, pool), color: REMAINDER_COLOR)
      add_link(links, center_index, node_index, remainder, percentage(remainder, pool))
    end

    {
      mode: mode.to_s,
      currency_symbol: Money::Currency.new(currency).symbol,
      base: decimal(pool),
      nodes: nodes,
      links: links
    }
  end

  private
    def amount_for(row, mode)
      case mode.to_sym
      when :ideal then row.ideal_amount
      when :budgeted then row.budgeted_amount
      when :actual then row.actual_amount
      else 0.to_d
      end
    end

    def source_value(mode)
      case mode.to_sym
      when :actual
        actual = @budget.actual_income.to_d
        [ actual, rows.sum(&:actual_amount), base ].max
      else
        base
      end
    end

    # In the ideal diagram, flows are colored by deviation so overspending reads
    # red at a glance. The other diagrams keep each category's own color.
    def node_color(row, mode)
      return row.category.color unless mode.to_sym == :ideal
      row.over_ideal? ? DESTRUCTIVE_COLOR : SUCCESS_COLOR
    end

    def root_budget_categories
      @budget.budget_categories.reject(&:subcategory?)
    end

    def allocations_by_category_id
      @allocations_by_category_id ||= IdealAllocation.where(family_id: @family.id).index_by(&:category_id)
    end

    def add_node(nodes, id:, name:, kind:, value:, percentage:, category: nil, color: nil)
      nodes << {
        id: id, name: name, kind: kind.to_s, value: decimal(value), percentage: decimal(percentage),
        category_id: category&.id,
        filter_value: category && !category.other_investments? ? category.filter_value : nil,
        color: color || category&.color
      }
      nodes.size - 1
    end

    def add_link(links, source, target, value, percentage)
      links << { source: source, target: target, value: decimal(value), percentage: decimal(percentage) }
    end

    def empty_sankey
      { mode: "empty", currency_symbol: Money::Currency.new(currency).symbol, base: "0.0", nodes: [], links: [] }
    end

    def percentage(value, total)
      total.zero? ? 0 : (value.to_d / total * 100).round(1)
    end

    def decimal(value)
      value.to_d.to_s("F")
    end
end
