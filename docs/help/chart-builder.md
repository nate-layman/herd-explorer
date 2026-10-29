# Chart builder: Explore, Chart builder tab (explore.html#chart)

Drag-and-drop charts, built with Graphic Walker. Each row of its data is one institution in one fiscal year. Every measure is its own field named "Category: measure", for example "Source of funds: All R&D" or "Federal agency: NASA", in whole dollars (personnel in people). NCSES publishes HERD in thousands of dollars; the chart builder multiplies by 1,000. Axis and legend labels abbreviate: K is thousands, M millions, B billions (1.27B is $1.27 billion). Tooltips show the exact amount. Other fields: year, institution, state, sector, public or private, highest degree, minority-serving, hbcu, medical school, land-grant, latitude, longitude. Latitude and longitude are each institution's location (see data-sources.md); they are only in the chart builder.

## Examples

The builder opens on **Start your own**, a blank chart, with a brief tip pointing at the examples. Buttons above the builder open ready-made charts, each in its own tab, which you can change:

- **Start your own**: a blank chart with every field listed.
- **R&D by institution type**: line chart, year on X, All R&D on Y, sector on Color.
- **NIH funding by institution type**: stacked bars of Health and Human Services (incl. NIH) funding by year and sector.
- **States, FY {last_year}**: horizontal bars of All R&D by state, largest first, filtered to {last_year}.
- **Federal vs. business funding, FY {last_year}**: scatter plot, one dot per institution, colored by sector.
- **Map, lower 48, FY {last_year}**: one dot per institution on a map, sized and colored by All R&D. A filter leaves out Alaska, Hawaii and the territories so the map opens on the continental U.S.; remove it from Filters to show them. To map another measure, drag it onto Color or Size.

## Making a chart

The Field List lists the measures alphabetically by category in their own scrolling box: scroll that box to find a measure, then drag it to a shelf.

1. Drag **year** from the Field List to **X-Axis**.
2. Drag a measure, such as "Source of funds: All R&D", to **Y-Axis**. Measures are summed by default; use the field's menu on the shelf to change the aggregation.
3. Drag **sector** or **state** to **Color** for one line or bar per group.
4. Drag a field to **Filters** to narrow the data, for example state to just Idaho, or year to {last_year}.
5. Change the chart type with the **Mark Type** menu in the toolbar: bar, line, area, scatter, box plot, table and more. It keeps your fields where they are. Transpose swaps the axes.
   The **Auto Viz** panel is different. It starts collapsed to a narrow strip at the right edge; click the strip to open it. Its chart types rebuild the chart from a recommendation, so fields can move between shelves or drop off, for example a field on Color. Use it to explore suggestions, and Undo in the toolbar to go back.
6. Drag a field off a shelf to remove it.

## Aggregation

The **Aggregation** button in the toolbar (the cube icon, on by default) decides whether rows are combined.

- **On**: institutions are combined into one value for each combination of the fields on the shelves. With year on X-Axis and sector on Color, each point is one sector in one year, adding up its institutions. The word on a measure's shelf ("sum") is how they are combined; click it for Mean, Median, Count, Min, Max, Variance or Standard Deviation. Use this for totals and trends by group.
- **Off**: every row is drawn as its own mark, and each row is one institution in one fiscal year. Use this to compare institutions one by one, such as a scatter plot with one dot per institution; filter to a single year, or each institution appears once per year. Line charts are rarely useful with aggregation off.

Use **+ New** next to the chart tabs to start another chart; the others stay open.

Charts are kept while you move around the site in the same browser tab: leave Explore and come back, and the chart builder reopens with your charts and the tab you had open. Closing the browser tab clears them. If you close an example's tab, its button above the builder opens a fresh copy.

## Tables in the chart builder

The Text Table mark makes a crosstab: dimensions on the axes and a measure as values. For nested grouping with subtotals, many measures at once, or CSV export, the Table tab is easier (pivot-tables.md).

## Note

Do not sum a total with its own parts: "Source of funds: All R&D" already includes "Source of funds: Federal government".
