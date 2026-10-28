# Pivot tables: Explore, Table tab (explore.html#table)

Each stored row is one institution, one fiscal year and one measure, with these fields: institution, state, sector (institution type), public or private, minority-serving, medical school, year, category, measure, unit, amount. Amounts are in dollars (personnel in people or FTEs). The table adds rows up.

## Quick views

One-click starting points above the table:

- Total R&D by institution type
- By state
- Top institutions
- Federal R&D by agency
- By field of research
- Raw data (every row as stored, no grouping)

Click one, then change it with the dropdowns. The dropdowns always show how the current view is set up.

## Build your own: the dropdowns

Set them in this order:

1. **Measure first.** Pick one measure, such as All R&D (under Source of funds) or Department of Energy (under Federal agency). Adding up rows from different measures counts the same dollars twice; for example, All R&D already includes Federal government. To compare several measures side by side, pick "Every Federal agency measure", "Every Field of research measure" or "Every Field of research, federal measure" (categories whose measures do not overlap), and put measure in Rows or Columns.
2. **Rows**: what runs down the side, for example sector, state or institution.
3. **then by**, **then by**: nest a second and third level, for example sector then state. Each level gets a subtotal and the grand total is the TOTAL row; click a row to expand or collapse it.
4. **Columns**: what runs across, usually year. Choose (none) for a single total column.

"(set in More settings)" in the Measure dropdown means the current filter was set in the full panel.

## More settings

Opens Perspective's full settings panel beside the table:

- **Group By** (rows) and **Split By** (columns) take any number of fields: drag fields from the All Columns list at the bottom of the panel into the empty slot, drag to reorder, drag out to remove.
- **Where** filters on any field, for example state == ID, year == {last_year}, or sector == R1. Several filters combine.
- **Order By** sorts; click a column header's sort arrow to sort too.
- **Columns** sets which values are shown and how they are aggregated (sum by default; also mean, count and others).

## Export

The export button in the toolbar above the table downloads the current view as CSV.

## Worked examples

- Idaho institutions every year: Rows institution, Columns year, Measure All R&D, then in More settings add Where state == ID.
- Institution type, then state: Rows sector, then by state, Columns year, Measure All R&D.
- Each federal agency by institution type for FY {last_year}: Rows measure, Columns sector, Measure "Every Federal agency measure", then Where year == {last_year}.
- R1 federal funding by agency: Rows measure, Columns year, Measure "Every Federal agency measure", then Where sector == R1.

The "How to build your own" button on the page opens these steps with Show me buttons that set each example up.

## Charts

The Table tab is for tables. For charts, use the Chart builder tab (chart-builder.md), or Trends and Compare.
