# NHS RTT Waiting Times Analysis
## 06 — Power BI Dashboard Build Guide

**Dashboard:** NHS Referral-to-Treatment Waiting Times  
**Analysis period:** April 2025 to July 2026  
**Primary source:** MySQL database `nhs_rtt_analysis`

## 1. Dashboard objective

Build an interactive four-page dashboard answering:

1. Is the overall RTT waiting list increasing or decreasing?
2. Is 18-week performance improving?
3. Are 52+, 65+ and 78+ week waits reducing?
4. Which providers have the greatest pressure?
5. Which specialties contribute most to pressure?
6. How is Gloucestershire Hospitals NHS Foundation Trust performing?

## 2. Connect Power BI to MySQL

In Power BI Desktop:

1. Go to **Home > Get data**.
2. Choose **MySQL database**.
3. Server: `localhost`
4. Database: `nhs_rtt_analysis`
5. Choose **Import** mode.
6. Load:
   - `vw_national_monthly`
   - `vw_provider_monthly`
   - `vw_specialty_monthly`

These are the SQL views created in `05_sql_analysis.sql`.

## 3. Check data types

Use these types:

- `reporting_month` → Date
- codes/names → Text
- pathway counts → Whole number
- percentages → Decimal number
- median/p92 waits → Decimal number

Do **not** multiply percentage columns by 100 again. They are already stored on a 0–100 scale.

## 4. Create a Date table

Create this calculated table:

```DAX
Date =
ADDCOLUMNS(
    CALENDAR(
        MIN(vw_national_monthly[reporting_month]),
        MAX(vw_national_monthly[reporting_month])
    ),
    "Year", YEAR([Date]),
    "Month Number", MONTH([Date]),
    "Month", FORMAT([Date], "MMM"),
    "Year Month", FORMAT([Date], "YYYY-MM"),
    "Month Year", FORMAT([Date], "MMM YYYY")
)
```

Mark `Date` as the date table.

Create active one-to-many relationships:

- `Date[Date]` → `vw_national_monthly[reporting_month]`
- `Date[Date]` → `vw_provider_monthly[reporting_month]`
- `Date[Date]` → `vw_specialty_monthly[reporting_month]`

Use single-direction filtering.

# 5. Dashboard pages

## Page 1 — Executive Overview

### KPI cards
Create six cards:

- Total Waiting
- % Within 18 Weeks
- 52+ Weeks
- 65+ Weeks
- 78+ Weeks
- MoM Waiting Change

### Main trend
**Line chart**
- X-axis: `Date[Date]`
- Y-axis: `Total Waiting`
- Title: **Total RTT Waiting List**

### 18-week trend
**Line chart**
- X-axis: `Date[Date]`
- Y-axis: `% Within 18 Weeks`
- Add a constant line at `92`
- Title: **RTT Performance Within 18 Weeks**

### Long-wait trend
**Line chart**
- 52+ Weeks
- 65+ Weeks
- 78+ Weeks
- Title: **Long-Wait Pathways**

### Slicer
Use `Date[Month Year]`.

For KPI cards, use single-select month filtering.

---

## Page 2 — Provider Performance

### Slicers
- Reporting month
- Provider name

### KPI cards
- Provider Count
- Provider Total Waiting
- Provider % Within 18 Weeks
- Provider 52+ Weeks

### Largest waiting lists
**Horizontal bar chart**
- Y-axis: provider name
- X-axis: total waiting
- Top 15
- Sort descending

### Lowest 18-week performance
**Horizontal bar chart**
- Y-axis: provider name
- X-axis: % within 18 weeks
- Sort ascending

Use a reasonable minimum waiting-list filter if needed so tiny denominators do not dominate the ranking.

### 52+ week pressure
**Bar chart**
- Provider name
- 52+ week waits
- Top 15

### Volume vs performance
**Scatter chart**
- X-axis: total waiting
- Y-axis: % within 18 weeks
- Details: provider name
- Size: 52+ week waits

### Provider table
Include:
- Provider Name
- Total Waiting
- % Within 18 Weeks
- Median Wait
- P92 Wait
- 52+ Weeks
- 65+ Weeks
- 78+ Weeks

---

## Page 3 — Specialty Analysis

Use `vw_specialty_monthly`.

### Slicers
- Reporting month
- Treatment function

### KPI cards
- Specialty Total Waiting
- Specialty % Within 18 Weeks
- Specialty 52+ Weeks

### Visuals
1. **Largest Treatment-Function Waiting Lists**
   - horizontal bar chart
   - treatment function vs total waiting
   - top 15

2. **18-Week Performance by Treatment Function**
   - bar chart
   - sort ascending

3. **52+ Week Waits by Treatment Function**
   - bar chart

4. **Specialty Trend**
   - line chart
   - X-axis: reporting month
   - Y-axis: total waiting
   - use the treatment-function slicer rather than displaying all specialties at once

5. **Specialty Summary Table**
   - Treatment Function
   - Total Waiting
   - % Within 18 Weeks
   - 52+ Weeks
   - 65+ Weeks
   - 78+ Weeks

---

## Page 4 — Gloucestershire Hospitals Deep Dive

Apply a page-level filter:

`provider_code = RTE`

### KPI cards
- Provider Total Waiting
- Provider % Within 18 Weeks
- Provider Median Wait
- Provider P92 Wait
- Provider 52+ Weeks

### Visuals

1. **Gloucestershire Hospitals — Total Waiting List**
   - line chart
   - month vs total waiting

2. **Gloucestershire 18-Week Performance**
   - line chart
   - month vs % within 18 weeks
   - 92% reference line

3. **Gloucestershire vs Overall RTT Performance**
   - line chart with Gloucestershire and overall % within 18 weeks

4. **Waiting List by Treatment Function**
   - bar chart

5. **Specialty Pressure Table**
   - Treatment Function
   - Total Waiting
   - % Within 18 Weeks
   - 52+ Weeks
   - Median Wait
   - P92 Wait

Sort the table by `% Within 18 Weeks` ascending to surface lower-performing active specialties.

# 6. Recommended navigation

Add four navigation buttons in the same place on every page:

`Overview | Providers | Specialties | Gloucestershire`

