# Compare page (compare.html)

See institutions' trends side by side.

## Controls

- **Add an institution**: start typing a name and pick it from the list. Each institution appears as a colored chip; click the x on a chip to remove it. The page starts with the University of Idaho, Boise State University and Idaho State University.
- **Measure**: the measure to chart (All R&D by default).
- **Show as** (radio buttons):
  - **Amount**: the measure as reported.
  - **Per full-time faculty member**: the measure divided by the institution's full-time instructional staff from IPEDS (NCES), which is not HERD data. The count is taken the November before each fiscal year, so FY {first_year} has none, and it is missing where HERD and IPEDS do not report the same campus (some systems, medical centers and joint reporting units). Instructional staff include faculty who do no research, so read it as R&D per faculty member, not per researcher. Hover shows the amount and the faculty count. The context median is the median of each institution's own ratio. Projections are off in this view, since they project amounts.
  - **Index (FY {first_year} = 100)**: compares growth among institutions of very different size.
- **Context**: "Median of each institution's type" draws a dashed line for the median institution in each selected institution's Carnegie type, for context. "None" hides those lines.
- **Show projection to FY {projection_last_year}**: adds each institution's projection with shaded uncertainty ranges. See projections.md.

## Sharing

The address bar updates with the chosen institutions, measure and view (?inst=...&measure=...&mode=faculty or mode=index), so you can copy the link to share or bookmark the exact comparison.

## Tips

- To compare groups (all R1s, a state) instead of individual institutions, use Trends.
- To see many institutions in a table, use Explore's Table tab with institution in Rows and a filter (pivot-tables.md).
