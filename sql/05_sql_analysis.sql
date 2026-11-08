-- NHS Referral-to-Treatment Waiting Times Analysis
-- 05_sql_analysis.sql
-- MySQL 8.0+
--
-- Analysis window: April 2025 to July 2026
--
-- Input files from 03_multi_month_data_preparation.ipynb:
--   1) rtt_provider_totals_apr2025_jul2026.csv
--   2) rtt_incomplete_provider_apr2025_jul2026_clean.csv
--
-- Import them into MySQL Workbench as:
--   rtt_provider_totals
--   rtt_full
--
-- The queries below demonstrate validation, KPI calculation,
-- trend analysis, provider ranking, specialty analysis,
-- Gloucestershire benchmarking and Power BI views.

CREATE DATABASE IF NOT EXISTS nhs_rtt_analysis;
USE nhs_rtt_analysis;


-- IMPORT INSTRUCTIONS
/*
 In MySQL Workbench:
 
 1. Right-click the `nhs_rtt_analysis` schema.
 2. Choose "Table Data Import Wizard".
 3. Import:
 rtt_provider_totals_apr2025_jul2026.csv
 as:
 rtt_provider_totals
 
 4. Import:
 rtt_incomplete_provider_apr2025_jul2026_clean.csv
 as:
 rtt_full
 
 Important columns should use these general types:
 
 reporting_month            DATE
 reporting_period           VARCHAR
 provider_code              VARCHAR
 provider_name              VARCHAR
 treatment_function_code    VARCHAR
 treatment_function         VARCHAR
 row_type                   VARCHAR
 total_waiting              BIGINT / INT
 within_18_weeks            BIGINT / INT
 over_18_weeks              BIGINT / INT
 pct_within_18_weeks        DECIMAL / DOUBLE
 pct_over_18_weeks          DECIMAL / DOUBLE
 median_wait_weeks          DECIMAL / DOUBLE
 p92_wait_weeks             DECIMAL / DOUBLE
 over_52_weeks              BIGINT / INT
 over_65_weeks              BIGINT / INT
 over_78_weeks              BIGINT / INT
 pct_over_52_weeks          DECIMAL / DOUBLE
 */


-- BASIC INSPECTION
SELECT *
FROM rtt_provider_totals
LIMIT 10;
SELECT *
FROM rtt_full
LIMIT 10;
SELECT 'rtt_provider_totals' AS table_name,
    COUNT(*) AS row_count
FROM rtt_provider_totals
UNION ALL
SELECT 'rtt_full',
    COUNT(*)
FROM rtt_full;


-- DATA QUALITY CHECKS

-- Coverage: expected 16 months.
SELECT MIN(reporting_month) AS first_month,
    MAX(reporting_month) AS latest_month,
    COUNT(DISTINCT reporting_month) AS number_of_months
FROM rtt_provider_totals;

-- Provider count by month.
SELECT reporting_month,
    reporting_period,
    COUNT(DISTINCT provider_code) AS providers
FROM rtt_provider_totals
GROUP BY reporting_month,
    reporting_period
ORDER BY reporting_month;

-- Duplicate provider-month rows.
SELECT reporting_month,
    provider_code,
    COUNT(*) AS duplicate_count
FROM rtt_provider_totals
GROUP BY reporting_month,
    provider_code
HAVING COUNT(*) > 1;
-- Expected: zero rows.

-- Ensure provider total table contains only provider totals.
SELECT row_type,
    COUNT(*) AS rows_count
FROM rtt_provider_totals
GROUP BY row_type;

-- Negative-count check.
SELECT COUNT(*) AS invalid_negative_rows
FROM rtt_provider_totals
WHERE total_waiting < 0
    OR within_18_weeks < 0
    OR over_18_weeks < 0
    OR over_52_weeks < 0
    OR over_65_weeks < 0
    OR over_78_weeks < 0;

-- Within-18 count cannot exceed total waiting.
SELECT COUNT(*) AS invalid_rows
FROM rtt_provider_totals
WHERE within_18_weeks > total_waiting;
-- 3.7 Missing waiting-time statistics.
SELECT SUM(median_wait_weeks IS NULL) AS missing_median_wait,
    SUM(p92_wait_weeks IS NULL) AS missing_p92_wait
FROM rtt_provider_totals;


-- INDEXES
CREATE INDEX idx_provider_month ON rtt_provider_totals (provider_code, reporting_month);
CREATE INDEX idx_reporting_month ON rtt_provider_totals (reporting_month);
CREATE INDEX idx_full_month_provider ON rtt_full (reporting_month, provider_code);
CREATE INDEX idx_full_treatment ON rtt_full (treatment_function_code, reporting_month);


-- OVERALL MONTHLY KPI TREND
/*
 Never calculate AVG(pct_within_18_weeks) for the overall KPI.
 That would give equal weight to small and large providers.
 
 Use:
 SUM(within_18_weeks) / SUM(total_waiting)
 */
SELECT reporting_month,
    reporting_period,
    COUNT(DISTINCT provider_code) AS providers,
    SUM(total_waiting) AS total_waiting,
    SUM(within_18_weeks) AS within_18_weeks,
    SUM(over_18_weeks) AS over_18_weeks,
    ROUND(
        100.0 * SUM(within_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_within_18_weeks,
    ROUND(
        100.0 * SUM(over_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_over_18_weeks,
    SUM(over_52_weeks) AS over_52_weeks,
    SUM(over_65_weeks) AS over_65_weeks,
    SUM(over_78_weeks) AS over_78_weeks
FROM rtt_provider_totals
GROUP BY reporting_month,
    reporting_period
ORDER BY reporting_month;


-- MONTH-ON-MONTH WAITING-LIST CHANGE
WITH monthly AS (
    SELECT reporting_month,
        reporting_period,
        SUM(total_waiting) AS total_waiting
    FROM rtt_provider_totals
    GROUP BY reporting_month,
        reporting_period
),
with_previous AS (
    SELECT reporting_month,
        reporting_period,
        total_waiting,
        LAG(total_waiting) OVER (
            ORDER BY reporting_month
        ) AS previous_month_waiting
    FROM monthly
)
SELECT reporting_month,
    reporting_period,
    total_waiting,
    previous_month_waiting,
    total_waiting - previous_month_waiting AS mom_absolute_change,
    ROUND(
        100.0 * (total_waiting - previous_month_waiting) / NULLIF(previous_month_waiting, 0),
        2
    ) AS mom_pct_change
FROM with_previous
ORDER BY reporting_month;


-- START-TO-END CHANGE
WITH monthly AS (
    SELECT reporting_month,
        SUM(total_waiting) AS total_waiting,
        SUM(within_18_weeks) AS within_18_weeks
    FROM rtt_provider_totals
    GROUP BY reporting_month
),
boundary AS (
    SELECT MIN(reporting_month) AS first_month,
        MAX(reporting_month) AS latest_month
    FROM monthly
),
start_values AS (
    SELECT m.*
    FROM monthly m
        JOIN boundary b ON m.reporting_month = b.first_month
),
latest_values AS (
    SELECT m.*
    FROM monthly m
        JOIN boundary b ON m.reporting_month = b.latest_month
)
SELECT s.reporting_month AS first_month,
    l.reporting_month AS latest_month,
    s.total_waiting AS first_total_waiting,
    l.total_waiting AS latest_total_waiting,
    l.total_waiting - s.total_waiting AS waiting_change,
    ROUND(
        100.0 * (l.total_waiting - s.total_waiting) / NULLIF(s.total_waiting, 0),
        2
    ) AS waiting_change_pct,
    ROUND(
        100.0 * s.within_18_weeks / NULLIF(s.total_waiting, 0),
        2
    ) AS first_pct_within_18,
    ROUND(
        100.0 * l.within_18_weeks / NULLIF(l.total_waiting, 0),
        2
    ) AS latest_pct_within_18,
    ROUND(
        (
            100.0 * l.within_18_weeks / NULLIF(l.total_waiting, 0)
        ) - (
            100.0 * s.within_18_weeks / NULLIF(s.total_waiting, 0)
        ),
        2
    ) AS pct_point_change_within_18
FROM start_values s
    CROSS JOIN latest_values l;


-- LONG-WAIT TREND
SELECT reporting_month,
    reporting_period,
    SUM(over_52_weeks) AS over_52_weeks,
    SUM(over_65_weeks) AS over_65_weeks,
    SUM(over_78_weeks) AS over_78_weeks,
    ROUND(
        100.0 * SUM(over_52_weeks) / NULLIF(SUM(total_waiting), 0),
        3
    ) AS pct_over_52_weeks,
    ROUND(
        100.0 * SUM(over_65_weeks) / NULLIF(SUM(total_waiting), 0),
        3
    ) AS pct_over_65_weeks,
    ROUND(
        100.0 * SUM(over_78_weeks) / NULLIF(SUM(total_waiting), 0),
        3
    ) AS pct_over_78_weeks
FROM rtt_provider_totals
GROUP BY reporting_month,
    reporting_period
ORDER BY reporting_month;


-- LATEST MONTH
SET @latest_month := (
        SELECT MAX(reporting_month)
        FROM rtt_provider_totals
    );
SELECT @latest_month AS latest_reporting_month;


-- TOP 15 PROVIDERS BY WAITING-LIST SIZE
SELECT provider_code,
    provider_name,
    total_waiting,
    within_18_weeks,
    over_18_weeks,
    pct_within_18_weeks,
    median_wait_weeks,
    p92_wait_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks
FROM rtt_provider_totals
WHERE reporting_month = @latest_month
ORDER BY total_waiting DESC
LIMIT 15;


-- LOWEST 18-WEEK PERFORMANCE
/*
 The 1,000-pathway filter is an analytical display threshold,
 not an NHS performance standard.
 */
SELECT provider_code,
    provider_name,
    total_waiting,
    pct_within_18_weeks,
    over_18_weeks,
    over_52_weeks,
    median_wait_weeks,
    p92_wait_weeks
FROM rtt_provider_totals
WHERE reporting_month = @latest_month
    AND total_waiting >= 1000
ORDER BY pct_within_18_weeks ASC,
    total_waiting DESC
LIMIT 15;


-- PROVIDERS WITH MOST 52+ WEEK WAITS
SELECT provider_code,
    provider_name,
    total_waiting,
    over_52_weeks,
    ROUND(
        100.0 * over_52_weeks / NULLIF(total_waiting, 0),
        3
    ) AS calculated_pct_over_52,
    pct_within_18_weeks
FROM rtt_provider_totals
WHERE reporting_month = @latest_month
ORDER BY over_52_weeks DESC,
    total_waiting DESC
LIMIT 15;


-- PROVIDER IMPROVEMENT / DETERIORATION
WITH provider_coverage AS (
    SELECT provider_code,
        COUNT(DISTINCT reporting_month) AS months_observed
    FROM rtt_provider_totals
    GROUP BY provider_code
),
first_month AS (
    SELECT MIN(reporting_month) AS first_month
    FROM rtt_provider_totals
),
last_month AS (
    SELECT MAX(reporting_month) AS last_month
    FROM rtt_provider_totals
),
start_data AS (
    SELECT r.provider_code,
        r.provider_name,
        r.total_waiting AS start_total_waiting,
        r.pct_within_18_weeks AS start_pct_within_18,
        r.over_52_weeks AS start_over_52
    FROM rtt_provider_totals r
        JOIN first_month f ON r.reporting_month = f.first_month
),
end_data AS (
    SELECT r.provider_code,
        r.provider_name,
        r.total_waiting AS latest_total_waiting,
        r.pct_within_18_weeks AS latest_pct_within_18,
        r.over_52_weeks AS latest_over_52
    FROM rtt_provider_totals r
        JOIN last_month l ON r.reporting_month = l.last_month
)
SELECT e.provider_code,
    e.provider_name,
    s.start_total_waiting,
    e.latest_total_waiting,
    -- Absolute change in waiting list
    CAST(e.latest_total_waiting AS SIGNED) - CAST(s.start_total_waiting AS SIGNED) AS waiting_change,
    -- Percentage change in waiting list
    ROUND(
        100.0 * (
            CAST(e.latest_total_waiting AS SIGNED) - CAST(s.start_total_waiting AS SIGNED)
        ) / NULLIF(s.start_total_waiting, 0),
        2
    ) AS waiting_change_pct,
    -- 18-week performance
    s.start_pct_within_18,
    e.latest_pct_within_18,
    ROUND(
        CAST(e.latest_pct_within_18 AS DECIMAL(10, 2)) - CAST(s.start_pct_within_18 AS DECIMAL(10, 2)),
        2
    ) AS within_18_change_pp,
    -- Patients waiting more than 52 weeks
    s.start_over_52,
    e.latest_over_52,
    CAST(e.latest_over_52 AS SIGNED) - CAST(s.start_over_52 AS SIGNED) AS over_52_change
FROM start_data s
    JOIN end_data e ON s.provider_code = e.provider_code
    JOIN provider_coverage c ON e.provider_code = c.provider_code
WHERE c.months_observed = 16
ORDER BY within_18_change_pp DESC;


-- TOP 15 MOST IMPROVED PROVIDERS
WITH coverage AS (
    SELECT provider_code,
        COUNT(DISTINCT reporting_month) AS months_observed
    FROM rtt_provider_totals
    GROUP BY provider_code
),
bounds AS (
    SELECT MIN(reporting_month) AS first_month,
        MAX(reporting_month) AS latest_month
    FROM rtt_provider_totals
),
start_data AS (
    SELECT r.provider_code,
        r.pct_within_18_weeks AS start_pct
    FROM rtt_provider_totals r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.first_month
),
end_data AS (
    SELECT r.provider_code,
        r.provider_name,
        r.pct_within_18_weeks AS latest_pct,
        r.total_waiting AS latest_total_waiting
    FROM rtt_provider_totals r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.latest_month
)
SELECT e.provider_code,
    e.provider_name,
    s.start_pct,
    e.latest_pct,
    ROUND(e.latest_pct - s.start_pct, 2) AS improvement_pp,
    e.latest_total_waiting
FROM start_data s
    JOIN end_data e ON s.provider_code = e.provider_code
    JOIN coverage c ON e.provider_code = c.provider_code
WHERE c.months_observed = 16
ORDER BY improvement_pp DESC
LIMIT 15;


-- TOP 15 LARGEST DETERIORATIONS
WITH coverage AS (
    SELECT provider_code,
        COUNT(DISTINCT reporting_month) AS months_observed
    FROM rtt_provider_totals
    GROUP BY provider_code
),
bounds AS (
    SELECT MIN(reporting_month) AS first_month,
        MAX(reporting_month) AS latest_month
    FROM rtt_provider_totals
),
start_data AS (
    SELECT r.provider_code,
        r.pct_within_18_weeks AS start_pct
    FROM rtt_provider_totals r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.first_month
),
end_data AS (
    SELECT r.provider_code,
        r.provider_name,
        r.pct_within_18_weeks AS latest_pct,
        r.total_waiting AS latest_total_waiting
    FROM rtt_provider_totals r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.latest_month
)
SELECT e.provider_code,
    e.provider_name,
    s.start_pct,
    e.latest_pct,
    ROUND(e.latest_pct - s.start_pct, 2) AS change_pp,
    e.latest_total_waiting
FROM start_data s
    JOIN end_data e ON s.provider_code = e.provider_code
    JOIN coverage c ON e.provider_code = c.provider_code
WHERE c.months_observed = 16
ORDER BY change_pp ASC
LIMIT 15;


-- LATEST SPECIALTY WAITING-LIST TOTALS
WITH specialty_latest AS (
    SELECT treatment_function_code,
        treatment_function,
        SUM(total_waiting) AS total_waiting,
        SUM(within_18_weeks) AS within_18_weeks,
        SUM(over_52_weeks) AS over_52_weeks,
        SUM(over_65_weeks) AS over_65_weeks,
        SUM(over_78_weeks) AS over_78_weeks
    FROM rtt_full
    WHERE reporting_month = @latest_month
        AND row_type = 'treatment_function'
    GROUP BY treatment_function_code,
        treatment_function
)
SELECT treatment_function_code,
    treatment_function,
    total_waiting,
    ROUND(
        100.0 * within_18_weeks / NULLIF(total_waiting, 0),
        2
    ) AS pct_within_18_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks
FROM specialty_latest
ORDER BY total_waiting DESC
LIMIT 15;


-- SPECIALTIES WITH MOST 52+ WEEK WAITS
SELECT treatment_function_code,
    treatment_function,
    SUM(total_waiting) AS total_waiting,
    SUM(over_52_weeks) AS over_52_weeks,
    ROUND(
        100.0 * SUM(within_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_within_18_weeks
FROM rtt_full
WHERE reporting_month = @latest_month
    AND row_type = 'treatment_function'
GROUP BY treatment_function_code,
    treatment_function
ORDER BY over_52_weeks DESC
LIMIT 15;


-- SPECIALTY CHANGE: FIRST TO LATEST MONTH
WITH bounds AS (
    SELECT MIN(reporting_month) AS first_month,
        MAX(reporting_month) AS latest_month
    FROM rtt_full
),
specialty_start AS (
    SELECT r.treatment_function_code,
        r.treatment_function,
        SUM(r.total_waiting) AS start_waiting,
        SUM(r.within_18_weeks) AS start_within_18,
        SUM(r.over_52_weeks) AS start_over_52
    FROM rtt_full r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.first_month
        AND r.row_type = 'treatment_function'
    GROUP BY r.treatment_function_code,
        r.treatment_function
),
specialty_latest AS (
    SELECT r.treatment_function_code,
        r.treatment_function,
        SUM(r.total_waiting) AS latest_waiting,
        SUM(r.within_18_weeks) AS latest_within_18,
        SUM(r.over_52_weeks) AS latest_over_52
    FROM rtt_full r
        CROSS JOIN bounds b
    WHERE r.reporting_month = b.latest_month
        AND r.row_type = 'treatment_function'
    GROUP BY r.treatment_function_code,
        r.treatment_function
)
SELECT l.treatment_function_code,
    l.treatment_function,
    s.start_waiting,
    l.latest_waiting,
    l.latest_waiting - s.start_waiting AS waiting_change,
    ROUND(
        100.0 * (l.latest_waiting - s.start_waiting) / NULLIF(s.start_waiting, 0),
        2
    ) AS waiting_change_pct,
    ROUND(
        100.0 * s.start_within_18 / NULLIF(s.start_waiting, 0),
        2
    ) AS start_pct_within_18,
    ROUND(
        100.0 * l.latest_within_18 / NULLIF(l.latest_waiting, 0),
        2
    ) AS latest_pct_within_18,
    ROUND(
        (
            100.0 * l.latest_within_18 / NULLIF(l.latest_waiting, 0)
        ) - (
            100.0 * s.start_within_18 / NULLIF(s.start_waiting, 0)
        ),
        2
    ) AS within_18_change_pp,
    l.latest_over_52 - s.start_over_52 AS over_52_change
FROM specialty_start s
    JOIN specialty_latest l ON s.treatment_function_code = l.treatment_function_code
ORDER BY waiting_change DESC;


-- GLOUCESTERSHIRE HOSPITALS NHS FOUNDATION TRUST
-- Provider code: RTE
SELECT reporting_month,
    reporting_period,
    provider_name,
    total_waiting,
    within_18_weeks,
    over_18_weeks,
    pct_within_18_weeks,
    median_wait_weeks,
    p92_wait_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks
FROM rtt_provider_totals
WHERE provider_code = 'RTE'
ORDER BY reporting_month;


-- GLOUCESTERSHIRE VS OVERALL 18-WEEK PERFORMANCE
WITH overall AS (
    SELECT reporting_month,
        ROUND(
            100.0 * SUM(within_18_weeks) / NULLIF(SUM(total_waiting), 0),
            2
        ) AS overall_pct_within_18
    FROM rtt_provider_totals
    GROUP BY reporting_month
),
glos AS (
    SELECT reporting_month,
        pct_within_18_weeks AS glos_pct_within_18
    FROM rtt_provider_totals
    WHERE provider_code = 'RTE'
)
SELECT g.reporting_month,
    g.glos_pct_within_18,
    o.overall_pct_within_18,
    ROUND(
        g.glos_pct_within_18 - o.overall_pct_within_18,
        2
    ) AS difference_pp
FROM glos g
    JOIN overall o ON g.reporting_month = o.reporting_month
ORDER BY g.reporting_month;


-- GLOUCESTERSHIRE SPECIALTIES: LATEST MONTH
SELECT treatment_function_code,
    treatment_function,
    total_waiting,
    pct_within_18_weeks,
    median_wait_weeks,
    p92_wait_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks
FROM rtt_full
WHERE reporting_month = @latest_month
    AND provider_code = 'RTE'
    AND row_type = 'treatment_function'
ORDER BY total_waiting DESC;


-- GLOUCESTERSHIRE LOWEST 18-WEEK SPECIALTY PERFORMANCE
SELECT treatment_function_code,
    treatment_function,
    total_waiting,
    pct_within_18_weeks,
    over_52_weeks,
    median_wait_weeks,
    p92_wait_weeks
FROM rtt_full
WHERE reporting_month = @latest_month
    AND provider_code = 'RTE'
    AND row_type = 'treatment_function'
    AND total_waiting > 0
ORDER BY pct_within_18_weeks ASC,
    total_waiting DESC
LIMIT 10;


-- POWER BI VIEWS
CREATE OR REPLACE VIEW vw_national_monthly AS
SELECT reporting_month,
    reporting_period,
    COUNT(DISTINCT provider_code) AS providers,
    SUM(total_waiting) AS total_waiting,
    SUM(within_18_weeks) AS within_18_weeks,
    SUM(over_18_weeks) AS over_18_weeks,
    ROUND(
        100.0 * SUM(within_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_within_18_weeks,
    ROUND(
        100.0 * SUM(over_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_over_18_weeks,
    SUM(over_52_weeks) AS over_52_weeks,
    SUM(over_65_weeks) AS over_65_weeks,
    SUM(over_78_weeks) AS over_78_weeks
FROM rtt_provider_totals
GROUP BY reporting_month,
    reporting_period;

CREATE OR REPLACE VIEW vw_provider_monthly AS
SELECT reporting_month,
    reporting_period,
    region_code,
    provider_code,
    provider_name,
    total_waiting,
    within_18_weeks,
    over_18_weeks,
    pct_within_18_weeks,
    pct_over_18_weeks,
    median_wait_weeks,
    p92_wait_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks,
    pct_over_52_weeks
FROM rtt_provider_totals;

CREATE OR REPLACE VIEW vw_specialty_monthly AS
SELECT reporting_month,
    reporting_period,
    treatment_function_code,
    treatment_function,
    SUM(total_waiting) AS total_waiting,
    SUM(within_18_weeks) AS within_18_weeks,
    SUM(over_18_weeks) AS over_18_weeks,
    ROUND(
        100.0 * SUM(within_18_weeks) / NULLIF(SUM(total_waiting), 0),
        2
    ) AS pct_within_18_weeks,
    SUM(over_52_weeks) AS over_52_weeks,
    SUM(over_65_weeks) AS over_65_weeks,
    SUM(over_78_weeks) AS over_78_weeks
FROM rtt_full
WHERE row_type = 'treatment_function'
GROUP BY reporting_month,
    reporting_period,
    treatment_function_code,
    treatment_function;

CREATE OR REPLACE VIEW vw_provider_specialty_monthly AS
SELECT reporting_month,
    reporting_period,
    region_code,
    provider_code,
    provider_name,
    treatment_function_code,
    treatment_function,
    total_waiting,
    within_18_weeks,
    over_18_weeks,
    pct_within_18_weeks,
    pct_over_18_weeks,
    median_wait_weeks,
    p92_wait_weeks,
    over_52_weeks,
    over_65_weeks,
    over_78_weeks,
    pct_over_52_weeks
FROM rtt_full
WHERE row_type = 'treatment_function';


-- VERIFY VIEWS
SELECT *
FROM vw_national_monthly
ORDER BY reporting_month;
SELECT *
FROM vw_provider_monthly
ORDER BY reporting_month,
    total_waiting DESC
LIMIT 20;
SELECT *
FROM vw_specialty_monthly
ORDER BY reporting_month,
    total_waiting DESC
LIMIT 20;