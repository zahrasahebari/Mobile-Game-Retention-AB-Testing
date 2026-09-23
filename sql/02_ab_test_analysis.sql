-- Compare core performance metrics between A/B test groups
SELECT
	testgroup,
	COUNT(*) AS participants,
	SUM(revenue) AS total_revenue,
	ROUND(AVG(revenue), 2) AS average_revenue_per_user,
	COUNT(*) FILTER (
		WHERE revenue > 0
	) AS paying_users,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE revenue > 0) / COUNT(*), 2
	) AS payer_conversion_rate_pct,
	ROUND(AVG(revenue) FILTER (
		WHERE revenue > 0
	), 2) AS average_revenue_per_payer,
	MAX(revenue) AS maximum_revenue
FROM raw.ab_test
GROUP BY testgroup
ORDER BY testgroup;

-- Compare revenue distribution among paying users
SELECT
	testgroup,
	MIN(revenue) AS minimum_payer_revenue,
	PERCENTILE_CONT(0.25) WITHIN GROUP(
		ORDER BY revenue
	) AS percentile_25,
	PERCENTILE_CONT(0.5) WITHIN GROUP(
		ORDER BY revenue
	) AS median_revenue,
	PERCENTILE_CONT(0.75) WITHIN GROUP(
		ORDER BY revenue
	) AS percentile_75,
	PERCENTILE_CONT(0.9) WITHIN GROUP(
		ORDER BY revenue
	) AS percentile_90,
	PERCENTILE_CONT(0.99) WITHIN GROUP(
		ORDER BY revenue
	) AS percentile_99,
	MAX(revenue) AS maximum_payer_revenue
FROM raw.ab_test
WHERE revenue > 0
GROUP BY testgroup
ORDER BY testgroup;

-- Identify payer-revenue outliers using the IQR method
WITH payer_quartiles AS (
	SELECT
		testgroup,
		PERCENTILE_CONT(0.25) WITHIN GROUP(
			ORDER BY revenue
		) AS q1,
		PERCENTILE_CONT(0.75) WITHIN GROUP (
			ORDER BY revenue
		) AS q3
	FROM raw.ab_test
	WHERE revenue > 0
	GROUP BY testgroup
),

outlier_boundaries AS (
	SELECT
		testgroup,
		q1,
		q3,
		q3 - q1 AS iqr,
		q3 + 1.5 * (q3 -q1) AS upper_outlier_boundary
	FROM payer_quartiles
)

SELECT
	a.testgroup,
	b.q1,
	b.q3,
	b.iqr,
	b.upper_outlier_boundary,
	COUNT(*) FILTER (
		WHERE a.revenue > b.upper_outlier_boundary
	) AS high_revenue_outliers
FROM raw.ab_test AS a
JOIN outlier_boundaries AS b
	ON a.testgroup = b.testgroup
WHERE revenue > 0
GROUP BY
	a.testgroup,
	b.q1,
	b.q3,
	b.iqr,
	b.upper_outlier_boundary
ORDER BY a.testgroup;

-- Measure the contribution of IQR-flagged revenue outliers
WITH payer_quartiles AS (
	SELECT
		testgroup,
		PERCENTILE_CONT(0.25) WITHIN GROUP(
			ORDER BY revenue
		) AS q1,
		PERCENTILE_CONT(0.75) WITHIN GROUP (
			ORDER BY revenue
		) AS q3
	FROM raw.ab_test
	WHERE revenue > 0
	GROUP BY testgroup
),

outlier_boundaries AS (
	SELECT
		testgroup,
		q3 + 1.5* (q3 - q1) AS upper_outlier_boundary
	FROM payer_quartiles
)

SELECT
	a.testgroup,
	COUNT(*) AS payer_users,
	COUNT(*) FILTER (
		WHERE a.revenue > b.upper_outlier_boundary
	) AS high_revenue_outliers,
	ROUND(
    100.0 * COUNT(*) FILTER (
        WHERE a.revenue > b.upper_outlier_boundary
    ) / COUNT(*),
    2
) AS outlier_share_of_payers_pct,
	COALESCE (
		SUM(a.revenue) FILTER (
			WHERE a.revenue > b.upper_outlier_boundary
		),
		0
	) AS revenue_outlier,
	ROUND(
		100.0 * COALESCE (
			SUM(a.revenue) FILTER (
				WHERE a.revenue > b.upper_outlier_boundary
			),
			0
	) / SUM(a.revenue),
	2
	) AS outlier_share_of_revenue_pct
FROM raw.ab_test AS a
JOIN outlier_boundaries AS b
	ON a.testgroup = b.testgroup
WHERE revenue > 0
GROUP BY a.testgroup
ORDER BY a.testgroup;

-- Compare group performance after excluding IQR-flagged revenue outliers
WITH payer_quartiles AS(
	SELECT
		testgroup,
		PERCENTILE_CONT(0.25) WITHIN GROUP(
			ORDER BY revenue
		) AS q1,
		PERCENTILE_CONT(0.75) WITHIN GROUP(
			ORDER BY revenue
		) AS q3
	FROM raw.ab_test
	WHERE revenue > 0
	GROUP BY testgroup
),

outlier_boundaries AS(
	SELECT
		testgroup,
		q3 + 1.5 * (q3 -q1) AS upper_outlier_boundary
	FROM payer_quartiles
)

SELECT
	a.testgroup,
	COUNT(*) AS participants_after_exclusion,
	SUM(a.revenue) AS revenue_after_exclusion,
	ROUND(AVG(a.revenue), 2) AS arpu_after_exclusion,
	COUNT(*) FILTER (
		WHERE a.revenue > 0
	) AS paying_users_after_exclusion,
	ROUND(
		AVG(a.revenue) FILTER (WHERE revenue > 0),
		2
	) AS arppu_after_exclusion
FROM raw.ab_test AS a
JOIN outlier_boundaries AS b
	ON a.testgroup = b.testgroup
WHERE a.revenue <= b.upper_outlier_boundary
GROUP BY a.testgroup
ORDER BY a.testgroup;