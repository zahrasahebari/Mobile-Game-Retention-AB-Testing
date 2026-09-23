-- ============================================================
-- MOBILE GAME RETENTION & A/B TESTING ANALYTICS
-- DATA QUALITY CHECKS
-- ============================================================


-- ------------------------------------------------------------
-- 1. TABLE SIZE VALIDATION
-- Confirm that PostgreSQL contains the expected source rows
-- ------------------------------------------------------------

SELECT
    'registrations' AS table_name,
    COUNT(*) AS row_count
FROM raw.registrations

UNION ALL

SELECT
    'authentications' AS table_name,
    COUNT(*) AS row_count
FROM raw.authentications

UNION ALL

SELECT
    'ab_test' AS table_name,
    COUNT(*) AS row_count
FROM raw.ab_test;

-- ------------------------------------------------------------
-- 2. NULL VALUE CHECKS
-- Identify missing values in every source column
-- ------------------------------------------------------------


-- Registration data
SELECT
	COUNT(*) FILTER (WHERE reg_ts IS NULL) AS null_reg_ts,
	COUNT(*) FILTER (WHERE uid IS NULL) AS null_uid
FROM raw.registrations;

-- Authentication data
SELECT
	COUNT(*) FILTER (WHERE auth_ts IS NULL) AS null_auth_ts,
	COUNT(*) FILTER (WHERE uid IS NULL) AS null_uid
FROM raw.authentications;

-- A/B test data
SELECT
	COUNT(*) FILTER (WHERE user_id IS NULL) AS null_user_id,
	COUNT(*) FILTER (WHERE revenue IS NULL) AS null_revenue,
	COUNT(*) FILTER (WHERE testgroup IS NULL) AS null_testgroup
FROM raw.ab_test;

-- ------------------------------------------------------------
-- 3. DUPLICATE AND UNIQUENESS CHECKS
-- Validate the expected row-level structure of each table
-- ------------------------------------------------------------


-- Registration data:
-- Each user is expected to have one registration record
SELECT
	COUNT(*) AS total_rows,
	COUNT(DISTINCT uid) AS distinct_users,
	COUNT(*) - COUNT(DISTINCT uid) AS duplicated_uid_rows
FROM raw.registrations;

-- Authentications data:
-- Repeated user IDs are expected, but repeated combinations
-- of user ID and authentication timestamp may be duplicates

SELECT
	COUNT(*) AS total_rows,
	COUNT(DISTINCT uid) AS distinct_users,
	COUNT(*) - COUNT(DISTINCT (uid, auth_ts)) AS duplicated_event_rows
FROM raw.authentications;

-- A/B-test data:
-- Each participant is expected to appear once
SELECT
	COUNT(*) AS total_rows,
	COUNT(DISTINCT user_id) AS distinct_users,
	COUNT(*) - COUNT(DISTINCT user_id) AS duplicated_user_rows
FROM raw.ab_test;

-- Check registration timestamp range
SELECT
	MIN(reg_ts) AS minimun_reg_ts,
	MAX(reg_ts) AS maximum_reg_ts,
	TO_TIMESTAMP(MIN(reg_ts)) AT TIME ZONE 'UTC' AS earliest_registration,
	TO_TIMESTAMP(MAX(reg_ts)) AT TIME ZONE 'UTC' AS latest_registration
FROM raw.registrations;

-- Check authentication timestamp range
SELECT
	MIN(auth_ts) AS minimum_auth_ts,
	MAX(auth_ts) AS maximum_auth_ts,
	TO_TIMESTAMP(MIN(auth_ts)) AT TIME ZONE 'UTC' AS earliest_authentication,
	TO_TIMESTAMP(MAX(auth_ts)) AT TIME ZONE 'UTC' AS latest_authentication
FROM raw.authentications;

-- Check for authentication records belonging to unregistered users
SELECT
	COUNT(*) AS authentication_events_without_registration,
	COUNT(DISTINCT a.uid) AS users_without_registration
FROM raw.authentications AS a
	WHERE NOT EXISTS (
		SELECT 1
		FROM raw.registrations AS r
		WHERE r.uid = a.uid
);

-- Check for authentication events occurring before registration
SELECT
	COUNT(*) AS events_before_registration,
	COUNT(DISTINCT a.uid) AS users_affected
FROM raw.authentications AS a
JOIN raw.registrations AS r
	ON a.uid = r.uid
WHERE a.auth_ts < r.reg_ts;

-- Compare each user's registration with their first authentication
WITH first_authentication AS(
	SELECT
		uid,
		MIN(auth_ts) AS first_auth_ts
	FROM raw.authentications
	GROUP BY uid
)

SELECT
	COUNT(*) AS total_users,
	COUNT(*) FILTER(
		WHERE first_auth_ts = r.reg_ts
	) AS first_auth_matches_registration,
	COUNT(*) FILTER(
		WHERE first_auth_ts < r.reg_ts
	) AS first_auth_before_registration,
	COUNT(*) FILTER(
		WHERE first_auth_ts > r.reg_ts
	) AS first_auth_after_registration
FROM raw.registrations AS r
JOIN first_authentication AS f
	ON r.uid = f.uid;

-- Check A/B test group values and participant counts
SELECT
	testgroup,
	COUNT(*) AS participant_count
FROM raw.ab_test
GROUP BY testgroup
ORDER BY testgroup;

-- Check the distribution and validity of revenue values
SELECT
	MIN(revenue) AS minimum_revenue,
	MAX(revenue) AS maximum_revenue,
	ROUND(AVG(revenue), 2) AS average_revenue,
	COUNT(*) FILTER (
		WHERE revenue = 0
	) AS zero_revenue_rows,
	COUNT(*) FILTER (
		WHERE revenue < 0
	) AS negative_revenue_rows,
	COUNT(*) FILTER(
		WHERE revenue > 0
	) AS paying_users
FROM raw.ab_test;

-- Inspect the ten highest revenue values
SELECT
	user_id,
	testgroup,
	revenue
FROM raw.ab_test
ORDER BY revenue DESC
LIMIT 10;