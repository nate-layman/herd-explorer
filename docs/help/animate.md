# Animate: Explore, Animate tab (explore.html#animate)

Charts that play through the survey years, FY {first_year} to FY {last_year}, one frame per fiscal year. Press **Play** under the chart, **Pause** to stop, or drag the year slider to a year. Hover a bar, line or dot for its amount. Built with Plotly.

The options are deliberately few: a short list of measures and a capped number of institutions, so every animation plays smoothly in the browser. For any other measure, or a chart the Animate tab cannot make, use the Chart builder (chart-builder.md) or the Table tab (pivot-tables.md).

## Examples

Buttons above the controls open ready-made animations, which you can then change:

- **Top 15 in NSF funding**: bar race of National Science Foundation funding, the 15 largest institutions each year. Of the measures offered, its top 15 changes rank the most from year to year.
- **States, computer science R&D**: bar race of computer and information sciences R&D, the 15 largest states.
- **Federal agencies at R1s**: bar race of each federal agency's R&D funding at R1 universities.
- **Federal vs. business funding**: moving scatter of the 100 institutions with the most All R&D in FY {last_year}, federal funding on X, business funding on Y, bubble size All R&D.
- **R&D map**: every institution on a U.S. map, dot size All R&D, growing and shrinking year by year.
- **Top 5 states over time**: line race of All R&D for the five largest states, drawn one year at a time.

## Animations

- **Bar race**: the largest groups each year, ranked; bars slide up and down as ranks change. Each bar keeps its own color through the years; hover an institution's bar for its institution type. The scale eases toward each year's largest bar, changing by at most 8% a year, so bar lengths compare within a year; read amounts from the labels at the end of each bar. **Show** picks what the bars are: Institutions, States or Institution types, for the chosen **Measure**; or Federal agencies, Fields of research or Sources of funds, which split total R&D into parts that do not overlap (Measure does not apply, and every part is shown). **How many**: top 10, 15 or 20.
- **Line race**: lines for the 5 or 8 groups largest in FY {last_year}, drawn year by year. Show and Measure work as in the bar race.
- **Moving scatter**: one bubble per institution, moving as its X and Y measures change. **How many**: the 50, 100 or 200 institutions with the most All R&D in FY {last_year}. Bubble size is All R&D, color is institution type. **Log scales** (on by default) spreads out the smaller institutions; with it on, an institution with zero on either measure sits out that year.
- **Map**: one dot per institution, sized by the measure and colored by institution type. **How many**: top 100, top 300 or every institution, by the measure in FY {last_year}. Alaska and Hawaii are drawn as insets; Puerto Rico and the other territories are not shown. Locations come from the IPEDS directory files (NCES), not HERD.

## Filters and speed

- **Institution type** and **State** narrow the institutions counted, for example only R1 universities or only Idaho. They are hidden when the bars or lines are themselves types or states.
- **Speed**: slow, normal or fast.

## Measures offered

All R&D; federal government, business, institution funds, state and local government and nonprofit funding; Health and Human Services (incl. NIH), NSF, Defense, Energy, NASA and Agriculture; life sciences, engineering, computer and information sciences and physical sciences; clinical trials; indirect costs; total research headcount. Amounts are nominal whole dollars (see data-sources.md).

## From the Ask page

Ask can draw any animation this tab can make: ask for one in plain words. Its **Open in Animate** link opens the same settings here. A link to this tab can carry settings in its address, for example explore.html?type=bar&show=states&measure=source_federal_government&n=15#animate; settings that are not on the menu are ignored and the first example opens instead.

## Reading the motion

Each frame is one fiscal year's reported values. The movement between frames is drawn by the animation and is not data: only the values at each year are reported. Every chart's note under it says what is shown and gives the source.
