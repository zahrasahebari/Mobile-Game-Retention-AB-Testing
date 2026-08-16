-- Create an analysis schema for transformed data
CREATE SCHEMA IF NOT EXISTS analytics;

-- Create a reusable event-level user activity view
CREATE OR REPLACE VIEW analytics.user_activity AS

SELECT
	uid,
	registration_datetime,
	authentication_datetime,
	registration_datetime::date AS registration_date,
	authentication_datetime::date AS authentication_date,
	authentication_datetime::date
		 - registration_datetime::date AS days_since_registration
FROM (
	SELECT
		a.uid,
		TO_TIMESTAMP(a.auth_ts) AT TIME ZONE 'UTC'
			AS authentication_datetime,
		TO_TIMESTAMP(r.reg_ts) AT TIME ZONE 'UTC'
			AS registration_datetime
	FROM raw.authentications AS a
	JOIN raw.registrations AS r
		ON a.uid = r.uid
) AS converted_activity;

-- Inspect transformed activity for the first five users
SELECT *
FROM analytics.user_activity
WHERE uid <= 5
ORDER BY uid, authentication_datetime;

-- Calculate exact Day 1, Day 7 and Day 30 retention
WITH dataset_end AS(
	SELECT
		MAX(authentication_date) AS maximum_observation_date
	FROM analytics.user_activity
),

user_retention_status AS (
	SELECT
		uid,
		registration_date,
		BOOL_OR(days_since_registration = 1) AS retained_day_1,
		BOOL_OR(days_since_registration = 7) AS retained_day_7,
		BOOL_OR(days_since_registration = 30) AS retained_day_30
	FROM analytics.user_activity
	GROUP BY uid, registration_date
)

SELECT
	d.maximum_observation_date,
	
	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 1
	) AS eligible_day_1_users,
	
	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 1
		  AND u.retained_day_1
	) AS retained_day_1_users,

	ROUND(100.0
		* COUNT(*) FILTER(
			WHERE u.registration_date
				<= d.maximum_observation_date - 1
			  AND u.retained_day_1
		)
		/ NULLIF(
			COUNT(*) FILTER(
				WHERE u.registration_date
					<= d.maximum_observation_date - 1
			),
			0
		),
		2
	) AS day_1_retention_rate_pct,

	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 7
	) AS eligible_day_7_users,

	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 7
		  AND u.retained_day_7
	) AS retained_day_7_users,

	ROUND(100.0
		*COUNT(*) FILTER(
			WHERE u.registration_date
				<= d.maximum_observation_date - 7
			  AND u.retained_day_7
	)/ NULLIF(
		COUNT(*) FILTER(
			WHERE u.registration_date
				<= d.maximum_observation_date - 7
			),
			0
		),
		2
	) AS day_7_retention_rate_pct,

	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 30
	) AS eligible_day_30_users,

	COUNT(*) FILTER(
		WHERE u.registration_date
			<= d.maximum_observation_date - 30
		  AND u.retained_day_30
	) AS retained_day_30_users,

	ROUND(100.0
	* COUNT(*) FILTER (
		WHERE u.registration_date
			<= d.maximum_observation_date - 30
		  AND u.retained_day_30
		)/ NULLIF(
			COUNT(*) FILTER(
				WHERE u.registration_date
					<= d.maximum_observation_date - 30
			),
			0
		),
		2
	) AS day_30_retention_rate_pct

FROM user_retention_status AS u
CROSS JOIN dataset_end AS d
GROUP BY d.maximum_observation_date;

-- Calculate the exact-day retention curve from Day 0 to Day 30
WITH dataset_end AS(
SELECT
	MAX(autheNtication_date) AS maximum_observation_date
FROM analytics.user_activity
),

retention_days AS(
	SELECT
		GENERATE_SERIES(0, 30) AS day_number
),

eligible_users AS (
SELECT
	d.day_number,
	COUNT(r.uid) AS eligible_users
FROM retention_days AS d
CROSS JOIN dataset_end AS e
JOIN raw.registrations AS r
	ON(
		TO_TIMESTAMP(r.reg_ts) AT TIME ZONE 'UTC'
		)::date <= e.maximum_observation_date - d.day_number
GROUP BY d.day_number
),

retained_users AS(
SELECT
	days_since_registration AS day_number,
	COUNT(DISTINCT uid) AS retained_users
FROM analytics.user_activity
WHERE days_since_registration BETWEEN 0 AND 30
GROUP BY days_since_registration
)

SELECT
	d.day_number,
	e.eligible_users,
	COALESCE(r.retained_users, 0) AS retained_users,
	ROUND(100.0
	* COALESCE(r.retained_users, 0)
	/ NULLIF(e.eligible_users, 0),
	2
	) AS retention_rate_pct
FROM retention_days AS d
JOIN eligible_users AS e
	ON d.day_number = e.day_number
LEFT JOIN retained_users AS r
	ON d.day_number = r.day_number
ORDER BY d.day_number;

-- Inspect registration cohort sizes by year
SELECT
	DATE_TRUNC(
		'year',
		TO_TIMESTAMP(reg_ts) AT TIME ZONE 'UTC'
	)::date AS registration_year,
	COUNT(*) AS registered_users
FROM raw.registrations
GROUP BY registration_year
ORDER BY registration_year;

-- Compare Day 1, Day 7 and Day 30 retention by monthly cohort
WITH dataset_end AS(
	SELECT
		MAX(authentication_date) AS maximum_observation_date
	FROM analytics.user_activity
),

user_retention_status AS(
	SELECT
		uid,
		registration_date,
		DATE_TRUNC(
			'month',
			registration_date
		)::date AS cohort_month,
		BOOL_OR(days_since_registration = 1) AS retained_day_1,
		BOOL_OR(days_since_registration = 7) AS retained_day_7,
		BOOL_OR(days_since_registration = 30) AS retained_day_30
	FROM analytics.user_activity
	GROUP BY uid, registration_date
),

cohort_counts AS(
	SELECT
		u.cohort_month,
		COUNT(*) AS cohort_size,
		
		COUNT(*) FILTER (
			WHERE u.registration_date
				<= d.maximum_observation_date - 1
		) AS eligible_day_1_users,

		COUNT(*) FILTER (
			WHERE u.registration_date
				<= d.maximum_observation_date - 1
			  AND u.retained_day_1
		) AS retained_day_1_users,

		COUNT(*) FILTER(
			WHERE u.registration_date
				<= d.maximum_observation_date - 7
		) AS eligible_day_7_users,

		COUNT(*) FILTER (
			WHERE u.registration_date
				<= d.maximum_observation_date - 7
			  AND u.retained_day_7
		) AS retained_day_7_users,

		COUNT(*) FILTER (
			WHERE u.registration_date
				<= d.maximum_observation_date - 30
		) AS eligible_day_30_users,

		COUNT(*) FILTER (
			WHERE u.registration_date
				<= d.maximum_observation_date - 30
			  AND u.retained_day_30
		) AS retained_day_30_users
	FROM user_retention_status AS u
	CROSS JOIN dataset_end AS d
	WHERE u.cohort_month >= DATE '2018-01-01'
	GROUP BY u.cohort_month
)

SELECT
	cohort_month,
	cohort_size,

	eligible_day_1_users,
	retained_day_1_users,

	ROUND(100.0
	* retained_day_1_users
	/ NULLIF(eligible_day_1_users, 0),
	2
	) AS day_1_retention_rate_pct,

	eligible_day_7_users,
	retained_day_7_users,

	ROUND(100.0
	* retained_day_7_users
	/NULLIF(eligible_day_7_users, 0),
	2
	) AS day_7_retention_rate_pct,

	eligible_day_30_users,
	retained_day_30_users,

	ROUND(100.0
		* retained_day_30_users
		/ NULLIF(eligible_day_30_users, 0)
	,
	2
	) AS day_30_retention_rate_pct
FROM cohort_counts
ORDER BY cohort_month;