import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="ideal-allocations-form"
// Lets the user enter ideal targets as either euro amounts or percentages of
// expected income, converts the inputs when the unit toggle is switched, and
// live-sums the current total so they can see how much they have allocated.
export default class extends Controller {
  static targets = [
    "input",
    "summary",
    "basisField",
    "modeButton",
    "prefix",
    "suffix",
  ];
  static values = {
    base: { type: Number, default: 0 },
    mode: { type: String, default: "amount" },
    currencySymbol: { type: String, default: "€" },
  };

  connect() {
    this.recalculate();
  }

  setMode(event) {
    const nextMode = event.params.mode;
    if (nextMode === this.modeValue) return;

    this.#convertInputs(this.modeValue, nextMode);
    this.modeValue = nextMode;

    if (this.hasBasisFieldTarget) this.basisFieldTarget.value = nextMode;
    this.#syncUnitAffordances();
    this.#syncActiveButton();
    this.recalculate();
  }

  recalculate() {
    const total = this.inputTargets.reduce((sum, input) => {
      const value = Number.parseFloat(input.value);
      return sum + (Number.isFinite(value) ? value : 0);
    }, 0);

    if (!this.hasSummaryTarget) return;

    const rounded = Math.round(total * 10) / 10;
    const label =
      this.modeValue === "amount"
        ? `${this.currencySymbolValue}${rounded}`
        : `${rounded}%`;
    const overAllocated = this.modeValue === "percent" && rounded > 100;

    this.summaryTarget.textContent = label;
    this.summaryTarget.classList.toggle("text-destructive", overAllocated);
    this.summaryTarget.classList.toggle("text-primary", !overAllocated);
  }

  // Rewrites each input's value from the old unit to the new one. Needs the
  // expected-income base to translate; without it, percentages cannot be
  // resolved to euros, so the values are left as entered.
  #convertInputs(fromMode, toMode) {
    if (this.baseValue <= 0) return;

    this.inputTargets.forEach((input) => {
      const value = Number.parseFloat(input.value);
      if (!Number.isFinite(value)) return;

      let converted;
      if (fromMode === "percent" && toMode === "amount") {
        converted = (value / 100) * this.baseValue;
      } else if (fromMode === "amount" && toMode === "percent") {
        converted = (value / this.baseValue) * 100;
      } else {
        return;
      }

      const decimals = toMode === "amount" ? 2 : 1;
      input.value = Number(converted.toFixed(decimals));
      input.step = toMode === "amount" ? "0.01" : "0.1";
    });
  }

  #syncUnitAffordances() {
    const isAmount = this.modeValue === "amount";
    this.prefixTargets.forEach((el) => {
      el.textContent = isAmount ? this.currencySymbolValue : "";
    });
    this.suffixTargets.forEach((el) => {
      el.textContent = isAmount ? "" : "%";
    });
  }

  #syncActiveButton() {
    this.modeButtonTargets.forEach((button) => {
      const active =
        button.dataset.idealAllocationsFormModeParam === this.modeValue;
      button.classList.toggle("segmented-control__segment--active", active);
      button.setAttribute("aria-pressed", active.toString());
    });
  }
}
