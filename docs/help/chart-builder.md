# Chart builder: Explore, Chart builder tab (explore.html#chart)

Drag-and-drop charts, built with Graphic Walker. Each row of its data is one institution in one fiscal year. Every measure is its own field named "Category: measure", for example "Source of funds: All R&D" or "Federal agency: NASA", in thousands of dollars (personnel in people). Other fields: year, institution, state, sector, public or private, highest degree, minority-serving, hbcu, medical school, land-grant.

## Examples

Buttons above the builder open ready-made charts, each in its own tab, which you can change:

- **Start your own**: a blank chart with every field listed.
- **R&D by institution type**: line chart, year on X, All R&D on Y, sector on Color.
- **NIH funding by institution type**: stacked bars of Health and Human Services (incl. NIH) funding by year and sector.
- **States, FY {last_year}**: horizontal bars of All R&D by state, largest first, filtered to {last_year}.
- **Federal vs. business funding, FY {last_year}**: scatter plot, one dot per institution, colored by sector.

## Making a chart

1. Drag **year** from the Field List to **X-Axis**.
2. Drag a measure, such as "Source of funds: All R&D", to **Y-Axis**. Measures are summed by default; use the field's menu on the shelf to change the aggregation.
3. Drag **sector** or **state** to **Color** for one line or bar per group.
4. Drag a field to **Filters** to narrow the data, for example state to just Idaho, or year to {last_year}.
5. Change the mark type in the toolbar or the chart-type panel: bar, stacked bar, line, area, scatter, box plot, text table and more. Transpose swaps the axes.
6. Drag a field off a shelf to remove it.

Use **+ New** next to the chart tabs to start another chart; the others stay open.

## Tables in the chart builder

The Text Table mark makes a crosstab: dimensions on the axes and a measure as values. For nested grouping with subtotals, many measures at once, or CSV export, the Table tab is easier (pivot-tables.md).

## Note

Do not sum a total with its own parts: "Source of funds: All R&D" already includes "Source of funds: Federal government".
