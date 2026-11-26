USE nyc_311_service;

-- 01 Overall project KPIs  (Fact only)

-- Q1. How many service requests are recorded in total?
SELECT COUNT(*) AS total_requests
FROM fact_service_request;

-- Q2. How many requests have each status, and what % of all requests does each represent?
SELECT
    status,
    COUNT(*) AS requests,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM fact_service_request
GROUP BY status
ORDER BY requests DESC;

-- Q3. What is the overall closure rate?
SELECT
    COUNT(*) AS total_requests,
    SUM(status = 'Closed') AS closed_requests,
    ROUND(100 * SUM(status = 'Closed') / COUNT(*), 2) AS closure_rate_pct
FROM fact_service_request;

-- Q4. How many requests are not marked Closed, broken down by status?
SELECT
    COALESCE(status, 'Unknown') AS status,
    COUNT(*) AS not_closed_requests
FROM fact_service_request
WHERE status IS NULL OR status <> 'Closed'
GROUP BY COALESCE(status, 'Unknown')
ORDER BY not_closed_requests DESC;

-- Q5. Mean and median resolution time for valid closed requests
WITH valid AS (
    SELECT
        Resolution_Hours AS h,
        ROW_NUMBER() OVER (ORDER BY Resolution_Hours) AS rn,
        COUNT(*) OVER () AS cnt
    FROM fact_service_request
    WHERE status = 'Closed'
      AND Resolution_Hours IS NOT NULL
      AND Resolution_Hours >= 0
)
SELECT
    MAX(cnt) AS valid_closed_requests,
    ROUND(AVG(h), 2) AS mean_resolution_hours,
    ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
			THEN h END), 2) AS median_resolution_hours
FROM valid;

-- Q6. % of valid closed requests resolved within 24 hours
SELECT
    COUNT(*) AS valid_closed_requests,
    SUM(Resolution_Hours <= 24) AS resolved_within_24h,
    ROUND(100 * SUM(Resolution_Hours <= 24) / COUNT(*), 2) AS pct_within_24h
FROM fact_service_request
WHERE status = 'Closed'
  AND Resolution_Hours IS NOT NULL
  AND Resolution_Hours >= 0;

-- Q7. % of valid closed requests that took more than 30 days (720 hours)
SELECT
    COUNT(*) AS valid_closed_requests,
    SUM(Resolution_Hours > 720) AS over_30_days,
    ROUND(100 * SUM(Resolution_Hours > 720) / COUNT(*), 2) AS pct_over_30_days
FROM fact_service_request
WHERE status = 'Closed'
  AND Resolution_Hours IS NOT NULL
  AND Resolution_Hours >= 0;

-- Q8. Valid closed requests per resolution band
SELECT
    CASE
        WHEN Resolution_Hours <= 24  THEN '1. <=24 hours'
        WHEN Resolution_Hours <= 168 THEN '2. >24-168 hours'
        WHEN Resolution_Hours <= 720 THEN '3. >168-720 hours'
        ELSE                              '4. >720 hours'
    END AS resolution_band,
    COUNT(*) AS requests,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_valid_closed
FROM fact_service_request
WHERE status = 'Closed'
  AND Resolution_Hours IS NOT NULL
  AND Resolution_Hours >= 0
GROUP BY resolution_band
ORDER BY resolution_band;


-- 02 Time analysis  (Fact + dim_date)

-- Q9. How many requests were created in each year and month?
SELECT
    YEAR(d.Created_Date) AS yr,
    d.Month_Number       AS mth,
    d.Created_Month_Name AS month_name,
    COUNT(*)             AS requests
FROM fact_service_request f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY YEAR(d.Created_Date), d.Month_Number, d.Created_Month_Name
ORDER BY yr, mth;

-- Q10. Month-over-month % change in request volume
WITH monthly AS (
    SELECT
        YEAR(d.Created_Date) AS yr,
        d.Month_Number       AS mth,
        COUNT(*)             AS requests
    FROM fact_service_request f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY YEAR(d.Created_Date), d.Month_Number
)
SELECT
    yr, mth, requests,
    LAG(requests) OVER (ORDER BY yr, mth) AS prev_month_requests,
    ROUND(100 * (requests - LAG(requests) OVER (ORDER BY yr, mth))
          / LAG(requests) OVER (ORDER BY yr, mth), 2) AS mom_change_pct
FROM monthly
ORDER BY yr, mth;

-- Q11. Calendar dates with the highest numbers of requests (Top 10)
SELECT
    d.Created_Date,
    d.Created_Day_Name,
    COUNT(*) AS requests
FROM fact_service_request f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.Created_Date, d.Created_Day_Name
ORDER BY requests DESC
LIMIT 10;

-- Q12. Average requests per calendar day in each month, including zero-request days
WITH RECURSIVE daily AS (
    SELECT d.Created_Date AS d, COUNT(*) AS requests
    FROM fact_service_request f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.Created_Date
),
bounds AS (
    SELECT MIN(d) AS d_min, MAX(d) AS d_max FROM daily
),
calendar AS (
    SELECT d_min AS d, d_max FROM bounds
    UNION ALL
    SELECT d + INTERVAL 1 DAY, d_max FROM calendar WHERE d < d_max
)
SELECT
    YEAR(c.d)  AS yr,
    MONTH(c.d) AS mth,
    COUNT(*)   AS calendar_days,
    SUM(COALESCE(dy.requests, 0)) AS total_requests,
    SUM(dy.requests IS NULL)      AS zero_request_days,
    ROUND(SUM(COALESCE(dy.requests, 0)) / COUNT(*), 2) AS avg_requests_per_day
FROM calendar c
LEFT JOIN daily dy ON dy.d = c.d
GROUP BY YEAR(c.d), MONTH(c.d)
ORDER BY yr, mth;

-- Q13. Requests created on each day of the week
SELECT
    d.Created_Day_Name,
    COUNT(*) AS requests,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM fact_service_request f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.Created_Day_Name, WEEKDAY(d.Created_Date)
ORDER BY WEEKDAY(d.Created_Date);   -- Monday = 0

-- Q14. Weekdays vs weekends: total and per calendar day
WITH RECURSIVE daily AS (
    SELECT d.Created_Date AS d, COUNT(*) AS requests
    FROM fact_service_request f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.Created_Date
),
bounds AS (
    SELECT MIN(d) AS d_min, MAX(d) AS d_max FROM daily
),
calendar AS (
    SELECT d_min AS d, d_max FROM bounds
    UNION ALL
    SELECT d + INTERVAL 1 DAY, d_max FROM calendar WHERE d < d_max
)
SELECT
    CASE WHEN WEEKDAY(c.d) >= 5 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*) AS calendar_days,
    SUM(COALESCE(dy.requests, 0)) AS total_requests,
    ROUND(SUM(COALESCE(dy.requests, 0)) / COUNT(*), 2) AS avg_requests_per_day
FROM calendar c
LEFT JOIN daily dy ON dy.d = c.d
GROUP BY day_type;

-- Q15. Creation hours with the highest request volumes (hour comes from the Fact)
SELECT
    HOUR(Created_Time) AS created_hour,
    COUNT(*) AS requests,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM fact_service_request
GROUP BY HOUR(Created_Time)
ORDER BY requests DESC;

-- Q16. Daytime (06:00-17:59) vs nighttime (18:00-05:59): count and share
SELECT
    CASE
        WHEN HOUR(Created_Time) BETWEEN 6 AND 17 THEN 'Daytime (06-17)'
        ELSE 'Nighttime (18-05)'
    END AS period,
    COUNT(*) AS requests,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM fact_service_request
GROUP BY period;

-- SETUP: flat view over the star schema

CREATE OR REPLACE VIEW vw_311 AS
SELECT
    f.ID, f.status, f.Resolution_Hours, f.Resolution_Category,
    f.Created_Time, f.Close_Time,
    HOUR(f.Created_Time)               AS created_hour,
    d.Created_Date, d.Closed_Date, d.Created_Day_Name,
    d.Created_Month_Name, d.Month_Number,
    YEAR(d.Created_Date)               AS created_year,
    WEEKDAY(d.Created_Date)            AS weekday_no,          -- Monday = 0
    CASE WHEN WEEKDAY(d.Created_Date) >= 5 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    CASE WHEN HOUR(f.Created_Time) BETWEEN 6 AND 17 THEN 'Daytime' ELSE 'Nighttime' END AS day_period,
    a.agency, a.agency_name,
    ch.channel,
    c.borough, c.community_board,
    cp.complaint_type, cp.descriptor,
    l.location_type,
    (f.status = 'Closed' AND f.Resolution_Hours IS NOT NULL AND f.Resolution_Hours >= 0) AS is_valid_closed
FROM fact_service_request f
LEFT JOIN dim_date      d  ON d.date_key        = f.date_key
LEFT JOIN dim_agency    a  ON a.agency_key      = f.agency_key
LEFT JOIN dim_channel   ch ON ch.channel_key    = f.channel_key
LEFT JOIN dim_city      c  ON c.city_key        = f.city_key
LEFT JOIN dim_complaint cp ON cp.complaint_key  = f.complaint_key
LEFT JOIN dim_location  l  ON l.Location_Key    = f.location_key;



-- 03 Borough analysis

-- Q17. Requests per borough and % of all requests
SELECT borough, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY borough
ORDER BY requests DESC;

-- Q18. Community boards with the highest request volumes (Top 20)
SELECT borough, community_board, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY borough, community_board
ORDER BY requests DESC
LIMIT 20;

-- Q19. Five most common complaint types within each borough
WITH ranked AS (
    SELECT borough, complaint_type, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY borough ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    GROUP BY borough, complaint_type
)
SELECT borough, rn AS rank_in_borough, complaint_type, requests
FROM ranked
WHERE rn <= 5
ORDER BY borough, rn;

-- Q20. Median resolution time in each borough
WITH v AS (
    SELECT borough, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY borough ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY borough) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT borough, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY borough
ORDER BY median_hours DESC;

-- Q21. % of valid closed requests per borough resolved within 24 hours
SELECT borough, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours <= 24) AS within_24h,
       ROUND(100 * SUM(Resolution_Hours <= 24) / COUNT(*), 2) AS pct_within_24h
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY borough
ORDER BY pct_within_24h DESC;

-- Q22. % of valid closed requests per borough that took more than 30 days
SELECT borough, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours > 720) AS over_30_days,
       ROUND(100 * SUM(Resolution_Hours > 720) / COUNT(*), 2) AS pct_over_30_days
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY borough
ORDER BY pct_over_30_days DESC;

-- Q23. Closure rate in each borough
SELECT borough, COUNT(*) AS requests,
       SUM(status = 'Closed') AS closed_requests,
       ROUND(100 * SUM(status = 'Closed') / COUNT(*), 2) AS closure_rate_pct
FROM vw_311
GROUP BY borough
ORDER BY closure_rate_pct DESC;

-- Q24. Monthly request volume and MoM change within each borough
WITH m AS (
    SELECT borough, created_year AS yr, Month_Number AS mth, COUNT(*) AS requests
    FROM vw_311
    GROUP BY borough, created_year, Month_Number
)
SELECT borough, yr, mth, requests,
       LAG(requests) OVER w AS prev_month_requests,
       ROUND(100 * (requests - LAG(requests) OVER w) / LAG(requests) OVER w, 2) AS mom_change_pct
FROM m
WINDOW w AS (PARTITION BY borough ORDER BY yr, mth)
ORDER BY borough, yr, mth;


-- 04 Agency performance

-- Q25. Requests per agency and share of all requests
SELECT agency, agency_name, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY agency, agency_name
ORDER BY requests DESC;

-- Q26. % of total requests handled by the three busiest agencies combined
WITH top3 AS (
    SELECT agency, COUNT(*) AS requests
    FROM vw_311
    GROUP BY agency
    ORDER BY requests DESC
    LIMIT 3
)
SELECT GROUP_CONCAT(agency ORDER BY requests DESC) AS top3_agencies,
       SUM(requests) AS top3_requests,
       ROUND(100 * SUM(requests) / (SELECT COUNT(*) FROM vw_311), 2) AS pct_of_total
FROM top3;

-- Q27. Non-closed requests per agency, by status
SELECT agency, COALESCE(status, 'Unknown') AS status, COUNT(*) AS not_closed_requests
FROM vw_311
WHERE status IS NULL OR status <> 'Closed'
GROUP BY agency, COALESCE(status, 'Unknown')
ORDER BY agency, not_closed_requests DESC;

-- Q28. Closure rate per agency
SELECT agency, COUNT(*) AS requests,
       SUM(status = 'Closed') AS closed_requests,
       ROUND(100 * SUM(status = 'Closed') / COUNT(*), 2) AS closure_rate_pct
FROM vw_311
GROUP BY agency
ORDER BY requests DESC;

-- Q29. Mean and median resolution time per agency
WITH v AS (
    SELECT agency, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY agency ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY agency) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT agency, MAX(cnt) AS valid_closed,
       ROUND(AVG(h), 2) AS mean_hours,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY agency
ORDER BY valid_closed DESC;

-- Q30. % of each agency's valid closed requests resolved within 24 hours
SELECT agency, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours <= 24) AS within_24h,
       ROUND(100 * SUM(Resolution_Hours <= 24) / COUNT(*), 2) AS pct_within_24h
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY agency
ORDER BY valid_closed DESC;

-- Q31. Agencies with the most requests taking more than 30 days (count and %)
SELECT agency, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours > 720) AS over_30_days,
       ROUND(100 * SUM(Resolution_Hours > 720) / COUNT(*), 2) AS pct_over_30_days
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY agency
ORDER BY over_30_days DESC
LIMIT 15;

-- Q32. Median resolution time per agency across boroughs (min 30 valid closed per pair)
WITH v AS (
    SELECT agency, borough, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY agency, borough ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY agency, borough) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
med AS (
    SELECT agency, borough, MAX(cnt) AS valid_closed,
           ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
    FROM v
    GROUP BY agency, borough
    HAVING MAX(cnt) >= 30
)
SELECT agency, borough, valid_closed, median_hours,
       ROUND(MAX(median_hours) OVER (PARTITION BY agency)
           - MIN(median_hours) OVER (PARTITION BY agency), 2) AS spread_across_boroughs
FROM med
ORDER BY spread_across_boroughs DESC, agency, median_hours DESC;


-- 05 Complaint-type analysis

-- Q33. Ten most common complaint types and their % of all requests
SELECT complaint_type, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY complaint_type
ORDER BY requests DESC
LIMIT 10;

-- Q34. Ten complaint types with the most non-closed requests
SELECT complaint_type, COUNT(*) AS not_closed_requests
FROM vw_311
WHERE status IS NULL OR status <> 'Closed'
GROUP BY complaint_type
ORDER BY not_closed_requests DESC
LIMIT 10;

-- Q35. Median resolution time for each of the ten most common complaint types
WITH top10 AS (
    SELECT complaint_type, COUNT(*) AS requests
    FROM vw_311 GROUP BY complaint_type ORDER BY requests DESC LIMIT 10
),
v AS (
    SELECT t.complaint_type, t.requests, w.Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY t.complaint_type ORDER BY w.Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY t.complaint_type) AS cnt
    FROM vw_311 w
    JOIN top10 t ON t.complaint_type = w.complaint_type
    WHERE w.is_valid_closed = 1
)
SELECT complaint_type, MAX(requests) AS requests, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY complaint_type
ORDER BY requests DESC;

-- Q36. Complaint types with >= 100 valid closed requests, highest median first
WITH v AS (
    SELECT complaint_type, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY complaint_type ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY complaint_type) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT complaint_type, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY complaint_type
HAVING MAX(cnt) >= 100
ORDER BY median_hours DESC
LIMIT 15;

-- Q37. Complaint types with the most requests taking more than 30 days
SELECT complaint_type, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours > 720) AS over_30_days,
       ROUND(100 * SUM(Resolution_Hours > 720) / COUNT(*), 2) AS pct_over_30_days
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY complaint_type
ORDER BY over_30_days DESC
LIMIT 15;

-- Q38. Top 5 descriptors within each of the five most frequent complaint types
WITH top5 AS (
    SELECT complaint_type FROM vw_311
    GROUP BY complaint_type ORDER BY COUNT(*) DESC LIMIT 5
),
ranked AS (
    SELECT w.complaint_type, w.descriptor, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY w.complaint_type ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311 w
    JOIN top5 t ON t.complaint_type = w.complaint_type
    GROUP BY w.complaint_type, w.descriptor
)
SELECT complaint_type, rn AS rank_in_type, descriptor, requests
FROM ranked
WHERE rn <= 5
ORDER BY complaint_type, rn;

-- Q39. Monthly volume (and MoM change) for the five most common complaint types
WITH top5 AS (
    SELECT complaint_type FROM vw_311
    GROUP BY complaint_type ORDER BY COUNT(*) DESC LIMIT 5
),
m AS (
    SELECT w.complaint_type, w.created_year AS yr, w.Month_Number AS mth, COUNT(*) AS requests
    FROM vw_311 w
    JOIN top5 t ON t.complaint_type = w.complaint_type
    GROUP BY w.complaint_type, w.created_year, w.Month_Number
)
SELECT complaint_type, yr, mth, requests,
       ROUND(100 * (requests - LAG(requests) OVER w) / LAG(requests) OVER w, 2) AS mom_change_pct
FROM m
WINDOW w AS (PARTITION BY complaint_type ORDER BY yr, mth)
ORDER BY complaint_type, yr, mth;

-- Q40. Agencies handling each of the ten most common complaint types
WITH top10 AS (
    SELECT complaint_type FROM vw_311
    GROUP BY complaint_type ORDER BY COUNT(*) DESC LIMIT 10
)
SELECT w.complaint_type, w.agency, w.agency_name, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY w.complaint_type), 2) AS pct_within_type
FROM vw_311 w
JOIN top10 t ON t.complaint_type = w.complaint_type
GROUP BY w.complaint_type, w.agency, w.agency_name
ORDER BY w.complaint_type, requests DESC;


--   06 Weekday/weekend and day/night comparisons (Daytime = 06:00-17:59, Nighttime = 18:00-05:59)


-- Q41. Five most common complaint types on weekdays and on weekends
WITH ranked AS (
    SELECT day_type, complaint_type, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY day_type ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    GROUP BY day_type, complaint_type
)
SELECT day_type, rn AS rank_no, complaint_type, requests
FROM ranked
WHERE rn <= 5
ORDER BY day_type, rn;

-- Q42. Five most common complaint types during daytime and nighttime
WITH ranked AS (
    SELECT day_period, complaint_type, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY day_period ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    GROUP BY day_period, complaint_type
)
SELECT day_period, rn AS rank_no, complaint_type, requests
FROM ranked
WHERE rn <= 5
ORDER BY day_period, rn;

-- Q43. % of requests occurring at night for each common complaint type (top 10; change LIMIT to widen)
WITH top10 AS (
    SELECT complaint_type FROM vw_311
    GROUP BY complaint_type ORDER BY COUNT(*) DESC LIMIT 10
)
SELECT w.complaint_type, COUNT(*) AS requests,
       SUM(w.day_period = 'Nighttime') AS night_requests,
       ROUND(100 * SUM(w.day_period = 'Nighttime') / COUNT(*), 2) AS pct_night
FROM vw_311 w
JOIN top10 t ON t.complaint_type = w.complaint_type
GROUP BY w.complaint_type
ORDER BY requests DESC;

-- Q44. Average daily volume on weekdays vs weekends per common complaint type
--      (denominator = ALL calendar days in the period, including zero-request days)
WITH RECURSIVE bounds AS (
    SELECT MIN(Created_Date) AS d_min, MAX(Created_Date) AS d_max FROM vw_311
),
cal AS (
    SELECT d_min AS d, d_max FROM bounds
    UNION ALL
    SELECT d + INTERVAL 1 DAY, d_max FROM cal WHERE d < d_max
),
day_counts AS (
    SELECT CASE WHEN WEEKDAY(d) >= 5 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
           COUNT(*) AS calendar_days
    FROM cal
    GROUP BY day_type
),
top10 AS (
    SELECT complaint_type FROM vw_311
    GROUP BY complaint_type ORDER BY COUNT(*) DESC LIMIT 10
),
vol AS (
    SELECT w.complaint_type, w.day_type, COUNT(*) AS requests
    FROM vw_311 w
    JOIN top10 t ON t.complaint_type = w.complaint_type
    GROUP BY w.complaint_type, w.day_type
)
SELECT v.complaint_type, v.day_type, v.requests, dc.calendar_days,
       ROUND(v.requests / dc.calendar_days, 2) AS avg_requests_per_day
FROM vol v
JOIN day_counts dc ON dc.day_type = v.day_type
ORDER BY v.complaint_type, v.day_type;

-- Q45. Median resolution time: weekday vs weekend creation
WITH v AS (
    SELECT day_type, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY day_type ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY day_type) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT day_type, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY day_type;

-- Q46. Median resolution time: daytime vs nighttime creation
WITH v AS (
    SELECT day_period, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY day_period ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY day_period) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT day_period, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY day_period;

-- Q47. Within each borough, the complaint type with the most nighttime requests
WITH ranked AS (
    SELECT borough, complaint_type, COUNT(*) AS night_requests,
           ROW_NUMBER() OVER (PARTITION BY borough ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    WHERE day_period = 'Nighttime'
    GROUP BY borough, complaint_type
)
SELECT borough, complaint_type, night_requests
FROM ranked
WHERE rn = 1
ORDER BY night_requests DESC;

-- Q48. Weekday + creation hour combinations with the highest volumes (Top 15)
SELECT Created_Day_Name, created_hour, COUNT(*) AS requests
FROM vw_311
GROUP BY Created_Day_Name, weekday_no, created_hour
ORDER BY requests DESC
LIMIT 15;

-- 07 Submission channels

-- Q49. Requests per channel and % of all requests
SELECT channel, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY channel
ORDER BY requests DESC;

-- Q50. Median resolution time per channel
WITH v AS (
    SELECT channel, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY channel ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY channel) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT channel, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM v
GROUP BY channel
ORDER BY median_hours;

-- Q51. Within each borough, % of requests by channel
SELECT borough, channel, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY borough), 2) AS pct_within_borough
FROM vw_311
GROUP BY borough, channel
ORDER BY borough, requests DESC;

-- Q52. Five most common complaint types for each channel
WITH ranked AS (
    SELECT channel, complaint_type, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY channel ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    GROUP BY channel, complaint_type
)
SELECT channel, rn AS rank_no, complaint_type, requests
FROM ranked
WHERE rn <= 5
ORDER BY channel, rn;

-- Q53. Channel usage by month (count and share of the month)
SELECT created_year AS yr, Month_Number AS mth, channel, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY created_year, Month_Number), 2) AS pct_of_month
FROM vw_311
GROUP BY created_year, Month_Number, channel
ORDER BY yr, mth, requests DESC;

-- Q54. Same complaint type + agency: median resolution time across channels
--      (min 30 valid closed per combination; only combos seen in 2+ channels)
WITH v AS (
    SELECT complaint_type, agency, channel, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY complaint_type, agency, channel ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY complaint_type, agency, channel) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
med AS (
    SELECT complaint_type, agency, channel, MAX(cnt) AS valid_closed,
           ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
    FROM v
    GROUP BY complaint_type, agency, channel
    HAVING MAX(cnt) >= 30
),
cmp AS (
    SELECT *,
           COUNT(*) OVER (PARTITION BY complaint_type, agency) AS channels_compared,
           ROUND(MAX(median_hours) OVER (PARTITION BY complaint_type, agency)
               - MIN(median_hours) OVER (PARTITION BY complaint_type, agency), 2) AS spread_hours
    FROM med
)
SELECT complaint_type, agency, channel, valid_closed, median_hours, spread_hours
FROM cmp
WHERE channels_compared >= 2
ORDER BY spread_hours DESC, complaint_type, agency, median_hours
LIMIT 60;


-- 08 Resolution categories and locations

-- Q55. Requests per resolution category and % of all requests
SELECT Resolution_Category, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY Resolution_Category
ORDER BY requests DESC;

-- Q56. Distribution across resolution categories among Closed requests
SELECT Resolution_Category, COUNT(*) AS closed_requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_closed
FROM vw_311
WHERE status = 'Closed'
GROUP BY Resolution_Category
ORDER BY closed_requests DESC;

-- Q57. Agencies with the most "Referred / Out of Jurisdiction" requests
SELECT agency, agency_name, COUNT(*) AS referred_requests
FROM vw_311
WHERE Resolution_Category = 'Referred / Out of Jurisdiction'
GROUP BY agency, agency_name
ORDER BY referred_requests DESC
LIMIT 10;

-- Q58. Complaint types most frequently receiving "No Violation / Condition Not Found"
SELECT complaint_type, COUNT(*) AS no_violation_requests
FROM vw_311
WHERE Resolution_Category = 'No Violation / Condition Not Found'
GROUP BY complaint_type
ORDER BY no_violation_requests DESC
LIMIT 10;

-- Q59. % of each agency's requests categorized as "Resolved - Action Taken"
SELECT agency, COUNT(*) AS requests,
       SUM(Resolution_Category = 'Resolved - Action Taken') AS action_taken,
       ROUND(100 * SUM(Resolution_Category = 'Resolved - Action Taken') / COUNT(*), 2) AS pct_action_taken
FROM vw_311
GROUP BY agency
ORDER BY requests DESC;

-- Q60. Requests with no resolution text or no matching resolution-category record
SELECT COUNT(*) AS total_requests,
       SUM(f.Resolution_Category = 'No Resolution Text')                  AS label_no_resolution_text,
       SUM(f.Resolution_Category IS NULL)                                 AS category_text_null,
       SUM(f.Category_Key IS NULL)                                        AS category_key_null,
       SUM(f.Category_Key IS NOT NULL AND rc.Category_Key IS NULL)        AS key_without_dim_match,
       SUM(f.Category_Key IS NULL OR rc.Category_Key IS NULL
           OR f.Resolution_Category = 'No Resolution Text')               AS any_of_the_above
FROM fact_service_request f
LEFT JOIN dim_res_category rc ON rc.Category_Key = f.Category_Key;

-- Q61. Location types with the highest request volumes
SELECT COALESCE(location_type, 'Unknown') AS location_type, COUNT(*) AS requests,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM vw_311
GROUP BY COALESCE(location_type, 'Unknown')
ORDER BY requests DESC
LIMIT 15;

-- Q62. Three most common complaint types within each location type
WITH ranked AS (
    SELECT COALESCE(location_type, 'Unknown') AS location_type, complaint_type, COUNT(*) AS requests,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(location_type, 'Unknown') ORDER BY COUNT(*) DESC) AS rn
    FROM vw_311
    GROUP BY COALESCE(location_type, 'Unknown'), complaint_type
)
SELECT location_type, rn AS rank_no, complaint_type, requests
FROM ranked
WHERE rn <= 3
ORDER BY location_type, rn;


-- 09 Data-quality checks

-- Q63. Duplicate or missing request IDs in raw, cleaned, and fact tables
--      (check that the raw table's ID column is really named ID)
SELECT 'raw' AS source, COUNT(*) AS total_rows, COUNT(DISTINCT ID) AS distinct_ids,
       SUM(ID IS NULL) AS null_ids, COUNT(ID) - COUNT(DISTINCT ID) AS duplicate_rows
FROM nyc_311_2024_all_months
UNION ALL
SELECT 'clean', COUNT(*), COUNT(DISTINCT ID), SUM(ID IS NULL), COUNT(ID) - COUNT(DISTINCT ID)
FROM nyc_311_2024_clean
UNION ALL
SELECT 'fact', COUNT(*), COUNT(DISTINCT ID), SUM(ID IS NULL), COUNT(ID) - COUNT(DISTINCT ID)
FROM fact_service_request;

-- Q64. Does the fact row count match the cleaned records? Which IDs are missing?
SELECT (SELECT COUNT(*) FROM nyc_311_2024_clean)  AS clean_rows,
       (SELECT COUNT(*) FROM fact_service_request) AS fact_rows,
       (SELECT COUNT(*) FROM nyc_311_2024_clean) - (SELECT COUNT(*) FROM fact_service_request) AS difference;

-- IDs in clean but missing from fact (first 100)
SELECT c.ID
FROM nyc_311_2024_clean c
LEFT JOIN fact_service_request f ON f.ID = c.ID
WHERE f.ID IS NULL
LIMIT 100;

-- IDs in fact but not in clean (first 100)
SELECT f.ID
FROM fact_service_request f
LEFT JOIN nyc_311_2024_clean c ON c.ID = f.ID
WHERE c.ID IS NULL
LIMIT 100;

-- Q65. Requests linked to missing dimension records (key NULL or key without a matching row)
SELECT COUNT(*) AS total_requests,
       SUM(f.agency_key    IS NULL OR a.agency_key     IS NULL) AS missing_agency,
       SUM(f.channel_key   IS NULL OR ch.channel_key   IS NULL) AS missing_channel,
       SUM(f.city_key      IS NULL OR c.city_key       IS NULL) AS missing_borough_city,
       SUM(f.complaint_key IS NULL OR cp.complaint_key IS NULL) AS missing_complaint,
       SUM(f.date_key      IS NULL OR d.date_key       IS NULL) AS missing_date,
       SUM(f.location_key  IS NULL OR l.Location_Key   IS NULL) AS missing_location,
       SUM(f.Category_Key  IS NULL OR rc.Category_Key  IS NULL) AS missing_resolution_category
FROM fact_service_request f
LEFT JOIN dim_agency       a  ON a.agency_key     = f.agency_key
LEFT JOIN dim_channel      ch ON ch.channel_key   = f.channel_key
LEFT JOIN dim_city         c  ON c.city_key       = f.city_key
LEFT JOIN dim_complaint    cp ON cp.complaint_key = f.complaint_key
LEFT JOIN dim_date         d  ON d.date_key       = f.date_key
LEFT JOIN dim_location     l  ON l.Location_Key   = f.location_key
LEFT JOIN dim_res_category rc ON rc.Category_Key  = f.Category_Key;

-- Q66. Closed with NULL resolution hours / non-closed with a recorded closing date
SELECT
    SUM(f.status = 'Closed' AND f.Resolution_Hours IS NULL)                         AS closed_null_resolution_hours,
    SUM((f.status IS NULL OR f.status <> 'Closed') AND d.Closed_Date IS NOT NULL)   AS non_closed_with_closed_date
FROM fact_service_request f
LEFT JOIN dim_date d ON d.date_key = f.date_key;

-- Q67. Closing timestamp earlier than creation timestamp (checked on the cleaned table;
--      run the same condition on the raw table with its own column names if cleaning already removed them)
SELECT COUNT(*) AS closed_before_created
FROM nyc_311_2024_clean
WHERE Closed_Date IS NOT NULL
  AND TIMESTAMP(Closed_Date, Closed_Time) < TIMESTAMP(Created_Date, Created_Time);

-- Q68. Requests with zero resolution hours, total and by agency
SELECT COALESCE(agency, 'ALL AGENCIES') AS agency, COUNT(*) AS zero_hour_requests
FROM vw_311
WHERE Resolution_Hours = 0
GROUP BY agency WITH ROLLUP
ORDER BY zero_hour_requests DESC;

-- Q69. % of requests with unknown borough, channel, agency, or complaint type
--      (unknown = NULL, empty, 'Unspecified', or 'Unknown')
SELECT 'borough' AS field,
       SUM(borough IS NULL OR TRIM(borough) IN ('', 'Unspecified', 'Unknown')) AS unknown_requests,
       ROUND(100 * SUM(borough IS NULL OR TRIM(borough) IN ('', 'Unspecified', 'Unknown')) / COUNT(*), 2) AS pct_unknown
FROM vw_311
UNION ALL
SELECT 'channel',
       SUM(channel IS NULL OR TRIM(channel) IN ('', 'Unspecified', 'Unknown')),
       ROUND(100 * SUM(channel IS NULL OR TRIM(channel) IN ('', 'Unspecified', 'Unknown')) / COUNT(*), 2)
FROM vw_311
UNION ALL
SELECT 'agency',
       SUM(agency IS NULL OR TRIM(agency) IN ('', 'Unspecified', 'Unknown')),
       ROUND(100 * SUM(agency IS NULL OR TRIM(agency) IN ('', 'Unspecified', 'Unknown')) / COUNT(*), 2)
FROM vw_311
UNION ALL
SELECT 'complaint_type',
       SUM(complaint_type IS NULL OR TRIM(complaint_type) IN ('', 'Unspecified', 'Unknown')),
       ROUND(100 * SUM(complaint_type IS NULL OR TRIM(complaint_type) IN ('', 'Unspecified', 'Unknown')) / COUNT(*), 2)
FROM vw_311;

-- Q70. Duplicate descriptive combinations in dimensions (any row > 0 can multiply rows in joins)
SELECT 'dim_agency' AS dim_table, COUNT(*) AS duplicate_groups
FROM (SELECT agency, agency_name FROM dim_agency GROUP BY agency, agency_name HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_channel', COUNT(*)
FROM (SELECT channel FROM dim_channel GROUP BY channel HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_city', COUNT(*)
FROM (SELECT community_board, borough FROM dim_city GROUP BY community_board, borough HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_complaint', COUNT(*)
FROM (SELECT complaint_type, descriptor FROM dim_complaint GROUP BY complaint_type, descriptor HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_location', COUNT(*)
FROM (SELECT location_type, latitude, longitude FROM dim_location GROUP BY location_type, latitude, longitude HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_res_category', COUNT(*)
FROM (SELECT resolution_description, category FROM dim_res_category GROUP BY resolution_description, category HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'dim_date', COUNT(*)
FROM (SELECT Created_Date, Closed_Date FROM dim_date GROUP BY Created_Date, Closed_Date HAVING COUNT(*) > 1) x;


-- 10 Advanced questions

-- Q71. 90th-percentile resolution time overall and per agency (nearest-rank method)
WITH v AS (
    SELECT agency, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY agency ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY agency) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
o AS (
    SELECT Resolution_Hours AS h,
           ROW_NUMBER() OVER (ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER () AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
)
SELECT 'ALL AGENCIES' AS scope, MAX(cnt) AS valid_closed,
       MAX(CASE WHEN rn = CEIL(0.9 * cnt) THEN h END) AS p90_hours
FROM o
UNION ALL
SELECT agency, MAX(cnt),
       MAX(CASE WHEN rn = CEIL(0.9 * cnt) THEN h END)
FROM v
GROUP BY agency;

-- Q72. Overall median resolution time with vs without NYPD
WITH a AS (
    SELECT Resolution_Hours AS h,
           ROW_NUMBER() OVER (ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER () AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
b AS (
    SELECT Resolution_Hours AS h,
           ROW_NUMBER() OVER (ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER () AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1 AND NOT (agency <=> 'NYPD')
)
SELECT 'All agencies' AS scope, MAX(cnt) AS valid_closed,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
FROM a
UNION ALL
SELECT 'Excluding NYPD', MAX(cnt),
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2)
FROM b;

-- Q73. Complaint types with high volume (top quartile) and their median resolution time
WITH vol AS (
    SELECT complaint_type, COUNT(*) AS requests
    FROM vw_311
    GROUP BY complaint_type
),
v AS (
    SELECT complaint_type, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY complaint_type ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY complaint_type) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
med AS (
    SELECT complaint_type, MAX(cnt) AS valid_closed,
           ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
    FROM v
    GROUP BY complaint_type
    HAVING MAX(cnt) >= 100
),
scored AS (
    SELECT vol.complaint_type, vol.requests, med.valid_closed, med.median_hours,
           NTILE(4) OVER (ORDER BY vol.requests)    AS volume_quartile,   -- 4 = highest volume
           NTILE(4) OVER (ORDER BY med.median_hours) AS median_quartile   -- 4 = slowest
    FROM vol
    JOIN med ON med.complaint_type = vol.complaint_type
)
SELECT *
FROM scored
WHERE volume_quartile = 4
ORDER BY median_hours DESC;

-- Q74. Borough-agency combinations contributing the most requests over 30 days
SELECT borough, agency, COUNT(*) AS valid_closed,
       SUM(Resolution_Hours > 720) AS over_30_days,
       ROUND(100 * SUM(Resolution_Hours > 720) / COUNT(*), 2) AS pct_over_30_days
FROM vw_311
WHERE is_valid_closed = 1
GROUP BY borough, agency
ORDER BY over_30_days DESC
LIMIT 15;

-- Q75. Age of still non-closed requests as of a reporting date (edit the date below)
SET @report_date = '2024-12-31';

SELECT status,
       COUNT(*) AS non_closed_requests,
       ROUND(AVG(age_days), 1) AS avg_age_days,
       MAX(age_days) AS oldest_age_days,
       SUM(age_days <= 7)                   AS age_0_7_days,
       SUM(age_days BETWEEN 8 AND 30)       AS age_8_30_days,
       SUM(age_days BETWEEN 31 AND 90)      AS age_31_90_days,
       SUM(age_days > 90)                   AS age_over_90_days
FROM (
    SELECT COALESCE(status, 'Unknown') AS status,
           DATEDIFF(@report_date, Created_Date) AS age_days
    FROM vw_311
    WHERE status IS NULL OR status <> 'Closed'
) x
GROUP BY status
ORDER BY non_closed_requests DESC;

-- Q76. Per creation month: % currently Closed + median resolution time of its valid closed requests
WITH m AS (
    SELECT created_year AS yr, Month_Number AS mth, Created_Month_Name AS month_name,
           COUNT(*) AS requests,
           SUM(status = 'Closed') AS closed_requests
    FROM vw_311
    GROUP BY created_year, Month_Number, Created_Month_Name
),
v AS (
    SELECT created_year AS yr, Month_Number AS mth, Resolution_Hours AS h,
           ROW_NUMBER() OVER (PARTITION BY created_year, Month_Number ORDER BY Resolution_Hours) AS rn,
           COUNT(*) OVER (PARTITION BY created_year, Month_Number) AS cnt
    FROM vw_311
    WHERE is_valid_closed = 1
),
med AS (
    SELECT yr, mth, MAX(cnt) AS valid_closed,
           ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2)) THEN h END), 2) AS median_hours
    FROM v
    GROUP BY yr, mth
)
SELECT m.yr, m.mth, m.month_name, m.requests, m.closed_requests,
       ROUND(100 * m.closed_requests / m.requests, 2) AS pct_closed,
       med.valid_closed, med.median_hours
FROM m
JOIN med ON med.yr = m.yr AND med.mth = m.mth
ORDER BY m.yr, m.mth;