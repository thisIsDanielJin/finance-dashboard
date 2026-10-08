import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { months: { type: Number, default: 3 } }

  connect() {
    this.initCharts()
    this.loadAll()
    this.updateButtons()
    window.addEventListener("resize", this.handleResize)
  }

  disconnect() {
    window.removeEventListener("resize", this.handleResize)
    this.charts().forEach(c => c?.dispose())
  }

  handleResize = () => this.charts().forEach(c => c?.resize())

  charts() {
    return [this.donut, this.bar, this.trends, this.networth]
  }

  initCharts() {
    const theme = document.documentElement.dataset.theme
    this.donut = echarts.init(document.getElementById("chart-donut"))
    this.bar = echarts.init(document.getElementById("chart-bar"))
    this.trends = echarts.init(document.getElementById("chart-trends"))
    this.networth = echarts.init(document.getElementById("chart-networth"))
  }

  setPeriod({ params: { months } }) {
    this.monthsValue = months
    this.updateButtons()
    this.loadAll()
  }

  updateButtons() {
    this.element.querySelectorAll("[data-period-btn]").forEach(btn => {
      const active = parseInt(btn.dataset.periodBtn) === this.monthsValue
      btn.classList.toggle("bg-surface-hover", active)
      btn.classList.toggle("text-primary", active)
      btn.classList.toggle("text-secondary", !active)
    })
  }

  async loadAll() {
    const m = this.monthsValue
    await Promise.all([
      this.loadSummary(),
      this.loadDonut(m),
      this.loadBar(m),
      this.loadTrends(m),
      this.loadNetWorth(m),
      this.loadMerchants(m)
    ])
  }

  fmt(v) {
    return new Intl.NumberFormat("de-DE", {
      style: "currency", currency: "EUR", minimumFractionDigits: 0, maximumFractionDigits: 0
    }).format(parseFloat(v) || 0)
  }

  palette() {
    return [
      "#3b82f6", "#22c55e", "#f59e0b", "#ef4444", "#a855f7",
      "#ec4899", "#06b6d4", "#f97316", "#6366f1", "#14b8a6",
      "#e11d48", "#8b5cf6", "#0ea5e9", "#84cc16", "#d946ef"
    ]
  }

  textColor() { return getComputedStyle(document.documentElement).getPropertyValue("--color-secondary").trim() || "#a1a1aa" }
  borderColor() { return "rgba(128,128,128,0.15)" }

  async loadSummary() {
    const data = await fetch("/analytics/summary.json").then(r => r.json())
    document.getElementById("stat-income").textContent = this.fmt(data.income_this_month)
    document.getElementById("stat-expenses").textContent = this.fmt(data.expenses_this_month)

    const net = (parseFloat(data.income_this_month) || 0) - (parseFloat(data.expenses_this_month) || 0)
    const el = document.getElementById("stat-savings")
    el.textContent = this.fmt(net)
    el.classList.toggle("text-success", net >= 0)
    el.classList.toggle("text-destructive", net < 0)

    const rateEl = document.getElementById("stat-rate")
    rateEl.textContent = data.savings_rate + "%"
    rateEl.classList.toggle("text-success", parseFloat(data.savings_rate) >= 0)
    rateEl.classList.toggle("text-destructive", parseFloat(data.savings_rate) < 0)

    const incChange = data.income_last_month > 0
      ? ((data.income_this_month - data.income_last_month) / data.income_last_month * 100).toFixed(1) : 0
    const expChange = data.expenses_last_month > 0
      ? ((data.expenses_this_month - data.expenses_last_month) / data.expenses_last_month * 100).toFixed(1) : 0

    const incEl = document.getElementById("stat-income-change")
    incEl.textContent = `${incChange >= 0 ? "+" : ""}${incChange}% vs last month`
    incEl.className = `text-xs mt-1 ${parseFloat(incChange) >= 0 ? "text-success" : "text-destructive"}`

    const expEl = document.getElementById("stat-expenses-change")
    expEl.textContent = `${expChange >= 0 ? "+" : ""}${expChange}% vs last month`
    expEl.className = `text-xs mt-1 ${parseFloat(expChange) <= 0 ? "text-success" : "text-destructive"}`
  }

  async loadDonut(months) {
    const data = await fetch(`/analytics/spending_by_category.json?months=${months}`).then(r => r.json())
    if (!data.length) {
      this.donut.clear()
      this.donut.setOption({ title: { text: "No spending data yet", left: "center", top: "center", textStyle: { color: this.textColor(), fontSize: 14 } } })
      return
    }
    this.donut.setOption({
      tooltip: { trigger: "item", formatter: (p) => `${p.name}: ${this.fmt(p.value)}<br/>${p.percent}%` },
      series: [{
        type: "pie", radius: ["45%", "75%"],
        itemStyle: { borderRadius: 6, borderColor: "transparent", borderWidth: 2 },
        label: { color: this.textColor(), fontSize: 11, formatter: "{b}\n{d}%" },
        emphasis: { label: { fontSize: 13, fontWeight: "bold" } },
        data: data.map((d, i) => ({
          name: d.category, value: parseFloat(d.total),
          itemStyle: { color: d.color || this.palette()[i % this.palette().length] }
        }))
      }]
    })
  }

  async loadBar(months) {
    const data = await fetch(`/analytics/income_vs_expenses.json?months=${months}`).then(r => r.json())
    if (!data.length) return
    const ms = data.map(d => d.month)
    const income = data.map(d => parseFloat(d.income) || 0)
    const expenses = data.map(d => parseFloat(d.expenses) || 0)
    const net = data.map((_, i) => income[i] - expenses[i])

    this.bar.setOption({
      tooltip: { trigger: "axis" },
      grid: { top: 30, right: 16, bottom: 24, left: 60 },
      xAxis: { type: "category", data: ms, axisLabel: { color: this.textColor(), fontSize: 11 }, axisLine: { lineStyle: { color: this.borderColor() } } },
      yAxis: { type: "value", axisLabel: { color: this.textColor(), fontSize: 11, formatter: v => this.fmt(v) }, splitLine: { lineStyle: { color: this.borderColor() } } },
      series: [
        { name: "Income", type: "bar", data: income, itemStyle: { color: "#22c55e", borderRadius: [4, 4, 0, 0] }, barMaxWidth: 24 },
        { name: "Expenses", type: "bar", data: expenses, itemStyle: { color: "#ef4444", borderRadius: [4, 4, 0, 0] }, barMaxWidth: 24 },
        { name: "Net", type: "line", data: net, smooth: true, symbol: "circle", symbolSize: 6, lineStyle: { color: "#3b82f6", width: 2 }, itemStyle: { color: "#3b82f6" } }
      ]
    })
  }

  async loadTrends(months) {
    const data = await fetch(`/analytics/spending_trends.json?months=${months}&limit=8`).then(r => r.json())
    if (!data.length) return
    const ms = [...new Set(data.map(d => d.month))].sort()
    const cats = [...new Set(data.map(d => d.category))]

    this.trends.setOption({
      tooltip: { trigger: "axis" },
      legend: { data: cats, bottom: 0, textStyle: { color: this.textColor(), fontSize: 11 }, icon: "circle", itemWidth: 8, itemHeight: 8 },
      grid: { top: 16, right: 16, bottom: 48, left: 60 },
      xAxis: { type: "category", data: ms, axisLabel: { color: this.textColor(), fontSize: 11 }, axisLine: { lineStyle: { color: this.borderColor() } } },
      yAxis: { type: "value", axisLabel: { color: this.textColor(), fontSize: 11, formatter: v => this.fmt(v) }, splitLine: { lineStyle: { color: this.borderColor() } } },
      series: cats.map((cat, i) => ({
        name: cat, type: "line", smooth: true, symbol: "circle", symbolSize: 5,
        lineStyle: { width: 2 }, areaStyle: { opacity: 0.05 },
        itemStyle: { color: this.palette()[i % this.palette().length] },
        data: ms.map(m => { const r = data.find(d => d.month === m && d.category === cat); return r ? parseFloat(r.total) : 0 })
      }))
    })
  }

  async loadNetWorth(months) {
    const data = await fetch(`/analytics/net_worth.json?months=${months}`).then(r => r.json())
    if (!data.length) {
      this.networth.clear()
      this.networth.setOption({ title: { text: "No balance data yet", left: "center", top: "center", textStyle: { color: this.textColor(), fontSize: 14 } } })
      return
    }
    const byDate = {}
    data.forEach(d => { byDate[d.date] = (byDate[d.date] || 0) + (parseFloat(d.balance) || 0) })
    const dates = Object.keys(byDate).sort()

    this.networth.setOption({
      tooltip: { trigger: "axis", formatter: (p) => `${p[0].axisValue}<br/>Net Worth: ${this.fmt(p[0].value)}` },
      grid: { top: 16, right: 16, bottom: 24, left: 60 },
      xAxis: { type: "category", data: dates.map(d => d.substring(0, 7)), axisLabel: { color: this.textColor(), fontSize: 11 }, axisLine: { lineStyle: { color: this.borderColor() } } },
      yAxis: { type: "value", axisLabel: { color: this.textColor(), fontSize: 11, formatter: v => this.fmt(v) }, splitLine: { lineStyle: { color: this.borderColor() } } },
      series: [{
        type: "line", data: dates.map(d => byDate[d]), smooth: true, symbol: "none",
        lineStyle: { color: "#a855f7", width: 2 },
        areaStyle: { color: { type: "linear", x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: "rgba(168,85,247,0.25)" }, { offset: 1, color: "rgba(168,85,247,0.02)" }] } }
      }]
    })
  }

  async loadMerchants(months) {
    const data = await fetch(`/analytics/top_merchants.json?months=${months}&limit=10`).then(r => r.json())
    const list = document.getElementById("merchant-list")
    if (!data.length) { list.innerHTML = '<li class="py-12 text-center text-secondary text-sm">No merchant data yet</li>'; return }
    list.innerHTML = data.map(d => `
      <li class="flex items-center justify-between py-3">
        <div>
          <p class="text-sm font-medium text-primary">${d.merchant}</p>
          <p class="text-xs text-secondary">${d.category}</p>
        </div>
        <div class="text-right">
          <p class="text-sm font-semibold tabular-nums text-primary">${this.fmt(d.total)}</p>
          <p class="text-xs text-secondary">${d.tx_count}x</p>
        </div>
      </li>
    `).join("")
  }
}
