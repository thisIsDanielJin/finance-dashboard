# Family-wide "ideal budget split" targets: one target per top-level category,
# edited together as a single set. Each target is entered either as a euro
# amount or a percentage of expected income (the form's unit toggle). Standing
# targets independent of any one month, consumed by Budget::IdealSplit.
class IdealAllocationsController < ApplicationController
  def edit
    @categories = Current.family.categories.roots.alphabetically
    @allocations = Current.family.ideal_allocations.index_by(&:category_id)
    @base = conversion_base
    @initial_basis = default_basis
    @return_to = sanitized_return_to
  end

  def update
    basis = IdealAllocation::BASES.include?(params[:basis]) ? params[:basis] : "percent"
    values = params.fetch(:values, {}).to_unsafe_h

    begin
      Current.family.transaction { upsert_allocations(basis, values) }
      redirect_to sanitized_return_to || budgets_path, notice: t("ideal_allocations.update.success")
    rescue ActiveRecord::RecordInvalid
      redirect_to edit_ideal_allocations_path(return_to: sanitized_return_to),
                  alert: t("ideal_allocations.update.invalid")
    end
  end

  private
    def upsert_allocations(basis, values)
      category_ids = Current.family.categories.roots.pluck(:id).to_set

      values.each do |category_id, raw|
        next unless category_ids.include?(category_id)

        allocation = Current.family.ideal_allocations.find_or_initialize_by(category_id: category_id)
        value = raw.to_s.strip

        if value.blank? || value.to_d.zero?
          allocation.destroy if allocation.persisted?
        else
          apply_value(allocation, basis, value.to_d)
          allocation.save!
        end
      end
    end

    def apply_value(allocation, basis, value)
      allocation.basis = basis
      if basis == "amount"
        allocation.amount = value
        allocation.percent = nil
      else
        allocation.percent = value
        allocation.amount = nil
      end
    end

    # Expected income of the current month's budget, used to convert between the
    # euro and percent views on the form. Zero when no budget has been set up.
    def conversion_base
      start_date, end_date = Budget.period_for(Date.current, family: Current.family)
      Current.family.budgets.find_by(start_date: start_date, end_date: end_date)&.expected_income.to_d
    end

    # Open the form in whatever unit the family last used, defaulting to euro.
    def default_basis
      Current.family.ideal_allocations.where(basis: "percent").exists? ? "percent" : "amount"
    end

    # Only allow returning to in-app budget paths, never an arbitrary URL.
    def sanitized_return_to
      candidate = params[:return_to].to_s
      candidate.start_with?("/budgets") ? candidate : nil
    end
end
