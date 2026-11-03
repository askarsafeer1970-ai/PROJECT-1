-- Social media impact project: MySQL 8.0+ analysis queries
-- Source: cleaned_projectdata.csv (4,500 student survey records)
-- Load the CSV into a table named social_media_survey before running these queries.
-- Requires MySQL 8.0+ for CTEs and window functions (NTILE).
-- Expected column names match the CSV headers below. Keep numeric columns numeric.
-- Late_Night_Usage should be 1/0 (TINYINT/BOOLEAN); convert imported True/False text if needed.
-- Interpretation: Sleep_Quality_Score appears to be 1-5; this script treats 1-2 as poor.
-- Perceived_Stress_Score is treated as a numeric scale; high stress is defined as >= 20.
-- Usage segments use dataset tertiles so thresholds are data-driven.

-- 1) Dataset coverage and basic quality checks
SELECT COUNT(*) AS respondent_count,
       COUNT(DISTINCT student_id) AS unique_students,
       SUM(perceived_stress_score IS NULL) AS missing_stress,
       SUM(academic_performance_gpa IS NULL) AS missing_gpa
FROM social_media_survey;

-- 2) Average daily time spent on social media (overall and weekend-adjusted view)
SELECT ROUND(AVG(daily_usage_hours), 2) AS avg_daily_usage_hours,
       ROUND(AVG(daily_usage_hours + weekend_extra_hours), 2) AS avg_weekend_usage_hours,
       ROUND(MIN(daily_usage_hours), 2) AS min_daily_usage_hours,
       ROUND(MAX(daily_usage_hours), 2) AS max_daily_usage_hours
FROM social_media_survey;

-- 3) Most-used primary platforms and platform usage rate
SELECT primary_platform,
       COUNT(*) AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS respondent_share_pct
FROM social_media_survey
GROUP BY primary_platform
ORDER BY respondents DESC;

-- 4) Usage distribution by low / medium / high users (tertiles)
WITH segmented AS (
    SELECT *, NTILE(3) OVER (ORDER BY daily_usage_hours) AS usage_tertile
    FROM social_media_survey
)
SELECT CASE usage_tertile WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' ELSE 'High' END AS usage_group,
       COUNT(*) AS respondents,
       ROUND(AVG(daily_usage_hours), 2) AS avg_daily_usage_hours,
       ROUND(MIN(daily_usage_hours), 2) AS min_hours,
       ROUND(MAX(daily_usage_hours), 2) AS max_hours
FROM segmented
GROUP BY usage_tertile
ORDER BY usage_tertile;

-- 5) Relationship between use and sleep duration / quality
SELECT CASE WHEN daily_usage_hours < 3 THEN 'Under 3 hours'
            WHEN daily_usage_hours < 6 THEN '3 to under 6 hours'
            ELSE '6+ hours' END AS usage_band,
       COUNT(*) AS respondents,
       ROUND(AVG(sleep_duration_hours), 2) AS avg_sleep_hours,
       ROUND(AVG(sleep_quality_score), 2) AS avg_sleep_quality_score,
       ROUND(100.0 * SUM(sleep_quality_score <= 2) / COUNT(*), 2) AS poor_sleep_rate_pct,
       ROUND(100.0 * SUM(late_night_usage = 1) / COUNT(*), 2) AS late_night_use_rate_pct
FROM social_media_survey
GROUP BY 1
ORDER BY MIN(daily_usage_hours);

-- Correlation coefficients use covariance / (population standard deviations), since MySQL has no CORR aggregate.
-- Values near -1/+1 indicate linear association, not causation.
SELECT ROUND((COVAR_POP(daily_usage_hours, sleep_duration_hours) / NULLIF(STDDEV_POP(daily_usage_hours) * STDDEV_POP(sleep_duration_hours), 0)), 3) AS usage_sleep_duration_corr,
       ROUND((COVAR_POP(daily_usage_hours, sleep_quality_score) / NULLIF(STDDEV_POP(daily_usage_hours) * STDDEV_POP(sleep_quality_score), 0)), 3) AS usage_sleep_quality_corr,
       ROUND((COVAR_POP(daily_usage_hours, CASE WHEN late_night_usage = 1 THEN 1 ELSE 0 END) / NULLIF(STDDEV_POP(daily_usage_hours) * STDDEV_POP(CASE WHEN late_night_usage = 1 THEN 1 ELSE 0 END), 0)), 3) AS usage_late_night_corr
FROM social_media_survey;

-- 6) Academic performance relationship (the dataset has GPA, not a direct productivity measure)
SELECT CASE WHEN daily_usage_hours < 3 THEN 'Under 3 hours'
            WHEN daily_usage_hours < 6 THEN '3 to under 6 hours'
            ELSE '6+ hours' END AS usage_band,
       COUNT(academic_performance_gpa) AS respondents_with_gpa,
       ROUND(AVG(academic_performance_gpa), 2) AS avg_gpa,
       ROUND((COVAR_POP(daily_usage_hours, academic_performance_gpa) / NULLIF(STDDEV_POP(daily_usage_hours) * STDDEV_POP(academic_performance_gpa), 0)), 3) AS usage_gpa_corr
FROM social_media_survey
GROUP BY 1
ORDER BY MIN(daily_usage_hours);

-- GPA distribution by late-night use
SELECT late_night_usage,
       COUNT(academic_performance_gpa) AS respondents_with_gpa,
       ROUND(AVG(academic_performance_gpa), 2) AS avg_gpa
FROM social_media_survey
GROUP BY late_night_usage
ORDER BY late_night_usage;

-- 7) Stress and mental-health indicator by usage group
-- The file contains stress score and Mental_Health_Index only; it has no separate
-- anxiety, loneliness, or self-esteem fields. Confirm index direction in the survey codebook.
WITH segmented AS (
    SELECT *, NTILE(3) OVER (ORDER BY daily_usage_hours) AS usage_tertile
    FROM social_media_survey
)
SELECT CASE usage_tertile WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' ELSE 'High' END AS usage_group,
       COUNT(perceived_stress_score) AS respondents_with_stress,
       ROUND(AVG(perceived_stress_score), 2) AS avg_stress_score,
       ROUND(100.0 * SUM(perceived_stress_score >= 20)
             / NULLIF(COUNT(perceived_stress_score), 0), 2) AS high_stress_rate_pct,
       ROUND(AVG(mental_health_index), 2) AS avg_mental_health_index
FROM segmented
GROUP BY usage_tertile
ORDER BY usage_tertile;

-- Approximate negative well-being composite from available fields only.
-- Stress is converted to a 0-100 scale assuming its maximum is 30; the index's direction
-- must be confirmed. This is not the requested stress/anxiety/loneliness/self-esteem score.
SELECT ROUND(AVG(100.0 * perceived_stress_score / 30.0), 2) AS avg_stress_component_0_100,
       ROUND(AVG(mental_health_index), 2) AS avg_mental_health_index
FROM social_media_survey
WHERE perceived_stress_score IS NOT NULL;

-- 8) Compare outcomes by age group, gender, and academic level (student status proxy)
SELECT CASE WHEN age < 18 THEN 'Under 18'
            WHEN age BETWEEN 18 AND 22 THEN '18-22'
            ELSE '23+' END AS age_group,
       gender,
       academic_level,
       COUNT(*) AS respondents,
       ROUND(AVG(daily_usage_hours), 2) AS avg_daily_usage_hours,
       ROUND(AVG(sleep_duration_hours), 2) AS avg_sleep_hours,
       ROUND(AVG(sleep_quality_score), 2) AS avg_sleep_quality,
       ROUND(AVG(perceived_stress_score), 2) AS avg_stress,
       ROUND(AVG(mental_health_index), 2) AS avg_mental_health_index,
       ROUND(AVG(academic_performance_gpa), 2) AS avg_gpa
FROM social_media_survey
GROUP BY 1, gender, academic_level
ORDER BY 1, gender, academic_level;

-- 9) Overall perceived effect and negative-impact KPI
SELECT overall_impact,
       COUNT(*) AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS respondent_share_pct
FROM social_media_survey
GROUP BY overall_impact
ORDER BY respondents DESC;

SELECT ROUND(100.0 * SUM(overall_impact = 'Negative') / COUNT(*), 2)
       AS perceived_negative_impact_rate_pct,
       ROUND(100.0 * SUM(overall_impact = 'Beneficial') / COUNT(*), 2)
       AS perceived_beneficial_impact_rate_pct,
       ROUND(100.0 * SUM(overall_impact = 'Neutral') / COUNT(*), 2)
       AS perceived_neutral_impact_rate_pct
FROM social_media_survey;

-- 10) High-vs-low usage KPI comparison (tertile groups)
WITH segmented AS (
    SELECT *, NTILE(3) OVER (ORDER BY daily_usage_hours) AS usage_tertile
    FROM social_media_survey
), outcomes AS (
    SELECT CASE usage_tertile WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' ELSE 'High' END AS usage_group,
           AVG(sleep_duration_hours) AS avg_sleep_hours,
           AVG(sleep_quality_score) AS avg_sleep_quality,
           AVG(perceived_stress_score) AS avg_stress,
           AVG(mental_health_index) AS avg_mental_health_index,
           AVG(academic_performance_gpa) AS avg_gpa,
           100.0 * SUM(overall_impact = 'Negative') / COUNT(*) AS negative_impact_pct
    FROM segmented
    WHERE usage_tertile IN (1, 3)
    GROUP BY usage_tertile
)
SELECT MAX(CASE WHEN usage_group = 'High' THEN avg_sleep_hours END)
       - MAX(CASE WHEN usage_group = 'Low' THEN avg_sleep_hours END) AS high_minus_low_sleep_hours,
       MAX(CASE WHEN usage_group = 'High' THEN avg_sleep_quality END)
       - MAX(CASE WHEN usage_group = 'Low' THEN avg_sleep_quality END) AS high_minus_low_sleep_quality,
       MAX(CASE WHEN usage_group = 'High' THEN avg_stress END)
       - MAX(CASE WHEN usage_group = 'Low' THEN avg_stress END) AS high_minus_low_stress,
       MAX(CASE WHEN usage_group = 'High' THEN avg_mental_health_index END)
       - MAX(CASE WHEN usage_group = 'Low' THEN avg_mental_health_index END) AS high_minus_low_mental_health_index,
       MAX(CASE WHEN usage_group = 'High' THEN avg_gpa END)
       - MAX(CASE WHEN usage_group = 'Low' THEN avg_gpa END) AS high_minus_low_gpa,
       MAX(CASE WHEN usage_group = 'High' THEN negative_impact_pct END)
       - MAX(CASE WHEN usage_group = 'Low' THEN negative_impact_pct END) AS high_minus_low_negative_impact_pct
FROM outcomes;

-- 11) Candidate audience for digital-wellbeing workshops / screen-time awareness
-- This identifies students with both heavy use (top tertile) and at least one adverse marker.
WITH segmented AS (
    SELECT *, NTILE(3) OVER (ORDER BY daily_usage_hours) AS usage_tertile
    FROM social_media_survey
)
SELECT COUNT(*) AS high_use_with_adverse_marker,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM segmented WHERE usage_tertile = 3), 2)
           AS share_of_high_use_group_pct
FROM segmented
WHERE usage_tertile = 3
  AND (sleep_quality_score <= 2
       OR perceived_stress_score >= 20
       OR overall_impact = 'Negative'
       OR academic_performance_gpa < 2.0);

-- Not computable from this CSV: actual anxiety, loneliness, self-esteem, work productivity,
-- explicit intention to reduce use, screen-time-limit willingness, or workshop preference.
-- Add survey columns for these measures before reporting those KPIs. The current file also
-- contains Academic_Level but no employed/student status field, so it cannot compare workers.

-- Optional MySQL reference table DDL if importing from CSV as typed columns:
-- CREATE TABLE social_media_survey (
--   Student_ID VARCHAR(30) PRIMARY KEY, Age INT, Gender VARCHAR(30), Academic_Level VARCHAR(50),
--   Primary_Platform VARCHAR(50), Daily_Usage_Hours DECIMAL(5,2), Weekend_Extra_Hours DECIMAL(5,2),
--   Device_Type VARCHAR(50), Sleep_Duration_Hours DECIMAL(5,2), Sleep_Quality_Score INT,
--   Late_Night_Usage TINYINT(1), Social_Comparison_Frequency VARCHAR(30),
--   Perceived_Stress_Score DECIMAL(5,2) NULL, Mental_Health_Index INT,
--   Academic_Performance_GPA DECIMAL(4,2) NULL, Overall_Impact VARCHAR(30)
-- );
