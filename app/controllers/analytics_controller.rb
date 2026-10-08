class AnalyticsController < ApplicationController
  def index
    @period_months = (params[:months] || 3).to_i
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ "Analytics", nil ] ]
  end

  def categorize_all
    uncategorized = Current.family.transactions.where(category_id: nil).pluck(:id)
    if uncategorized.any?
      Current.family.auto_categorize_transactions_later(
        Current.family.transactions.where(id: uncategorized)
      )
      redirect_to analytics_path, notice: "Categorizing #{uncategorized.count} transactions in the background."
    else
      redirect_to analytics_path, notice: "All transactions are already categorized."
    end
  end

  # --- JSON API endpoints for ECharts ---

  def spending_by_category
    months = sanitize_months(params[:months])
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "spending_by_category", [ Current.family.id ])
      SELECT
        COALESCE(c.name, 'Uncategorized') AS category,
        COALESCE(pc.name, c.name, 'Uncategorized') AS parent_category,
        c.color,
        SUM(ABS(e.amount)) AS total,
        COUNT(*) AS tx_count
      FROM entries e
      JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
      JOIN accounts a ON a.id = e.account_id
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN categories pc ON pc.id = c.parent_id
      WHERE e.amount > 0
        AND e.date >= CURRENT_DATE - INTERVAL '#{months} months'
        AND a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND e.excluded = false
      GROUP BY c.name, pc.name, c.color
      ORDER BY total DESC
    SQL
    render json: result.to_a
  end

  def income_vs_expenses
    months = sanitize_months(params[:months], default: 12)
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "income_vs_expenses", [ Current.family.id ])
      SELECT
        TO_CHAR(e.date, 'YYYY-MM') AS month,
        SUM(CASE WHEN e.amount > 0 THEN ABS(e.amount) ELSE 0 END) AS expenses,
        SUM(CASE WHEN e.amount < 0 THEN ABS(e.amount) ELSE 0 END) AS income
      FROM entries e
      JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
      JOIN accounts a ON a.id = e.account_id
      WHERE e.date >= CURRENT_DATE - INTERVAL '#{months} months'
        AND a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND e.excluded = false
      GROUP BY TO_CHAR(e.date, 'YYYY-MM')
      ORDER BY month
    SQL
    render json: result.to_a
  end

  def spending_trends
    months = sanitize_months(params[:months], default: 6)
    limit = sanitize_limit(params[:limit], default: 8)
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "spending_trends", [ Current.family.id ])
      WITH top_categories AS (
        SELECT COALESCE(c.name, 'Uncategorized') AS category
        FROM entries e
        JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
        JOIN accounts a ON a.id = e.account_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE e.amount > 0
          AND e.date >= CURRENT_DATE - INTERVAL '#{months} months'
          AND a.family_id = $1
          AND a.status IN ('draft', 'active')
          AND e.excluded = false
        GROUP BY c.name
        ORDER BY SUM(ABS(e.amount)) DESC
        LIMIT #{limit}
      )
      SELECT
        TO_CHAR(e.date, 'YYYY-MM') AS month,
        COALESCE(c.name, 'Uncategorized') AS category,
        SUM(ABS(e.amount)) AS total
      FROM entries e
      JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
      JOIN accounts a ON a.id = e.account_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE e.amount > 0
        AND e.date >= CURRENT_DATE - INTERVAL '#{months} months'
        AND a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND e.excluded = false
        AND COALESCE(c.name, 'Uncategorized') IN (SELECT category FROM top_categories)
      GROUP BY TO_CHAR(e.date, 'YYYY-MM'), c.name
      ORDER BY month, total DESC
    SQL
    render json: result.to_a
  end

  def net_worth
    months = sanitize_months(params[:months], default: 12)
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "net_worth", [ Current.family.id ])
      SELECT
        TO_CHAR(ab.date, 'YYYY-MM-DD') AS date,
        a.name AS account_name,
        a.accountable_type AS account_type,
        ab.balance
      FROM account_balances ab
      JOIN accounts a ON a.id = ab.account_id
      WHERE ab.date >= CURRENT_DATE - INTERVAL '#{months} months'
        AND a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND ab.date = (
          SELECT MAX(ab2.date)
          FROM account_balances ab2
          WHERE ab2.account_id = ab.account_id
            AND TO_CHAR(ab2.date, 'YYYY-MM') = TO_CHAR(ab.date, 'YYYY-MM')
        )
      ORDER BY ab.date
    SQL
    render json: result.to_a
  end

  def top_merchants
    months = sanitize_months(params[:months])
    limit = sanitize_limit(params[:limit], default: 15)
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "top_merchants", [ Current.family.id ])
      SELECT
        COALESCE(m.name, e.name, 'Unknown') AS merchant,
        COALESCE(c.name, 'Uncategorized') AS category,
        SUM(ABS(e.amount)) AS total,
        COUNT(*) AS tx_count
      FROM entries e
      JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
      JOIN accounts a ON a.id = e.account_id
      LEFT JOIN merchants m ON m.id = t.merchant_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE e.amount > 0
        AND e.date >= CURRENT_DATE - INTERVAL '#{months} months'
        AND a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND e.excluded = false
      GROUP BY COALESCE(m.name, e.name, 'Unknown'), c.name
      ORDER BY total DESC
      LIMIT #{limit}
    SQL
    render json: result.to_a
  end

  def summary
    result = ActiveRecord::Base.connection.exec_query(<<~SQL, "summary", [ Current.family.id ])
      SELECT
        SUM(CASE WHEN e.amount < 0 AND e.date >= DATE_TRUNC('month', CURRENT_DATE) THEN ABS(e.amount) ELSE 0 END) AS income_this_month,
        SUM(CASE WHEN e.amount > 0 AND e.date >= DATE_TRUNC('month', CURRENT_DATE) THEN ABS(e.amount) ELSE 0 END) AS expenses_this_month,
        SUM(CASE WHEN e.amount < 0 AND e.date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month') AND e.date < DATE_TRUNC('month', CURRENT_DATE) THEN ABS(e.amount) ELSE 0 END) AS income_last_month,
        SUM(CASE WHEN e.amount > 0 AND e.date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month') AND e.date < DATE_TRUNC('month', CURRENT_DATE) THEN ABS(e.amount) ELSE 0 END) AS expenses_last_month
      FROM entries e
      JOIN transactions t ON t.id = e.entryable_id AND e.entryable_type = 'Transaction'
      JOIN accounts a ON a.id = e.account_id
      WHERE a.family_id = $1
        AND a.status IN ('draft', 'active')
        AND e.excluded = false
    SQL
    row = result.first
    income = row["income_this_month"].to_f
    expenses = row["expenses_this_month"].to_f
    savings_rate = income > 0 ? ((income - expenses) / income * 100).round(1) : 0
    render json: row.merge("savings_rate" => savings_rate)
  end

  private

    # Sanitize integer params to prevent SQL injection.
    # months/limit are interpolated into INTERVAL/LIMIT clauses which
    # don't support $N placeholders in PostgreSQL.
    def sanitize_months(value, default: 3)
      v = value.to_i
      v > 0 && v <= 120 ? v : default
    end

    def sanitize_limit(value, default: 15)
      v = value.to_i
      v > 0 && v <= 100 ? v : default
    end
end
