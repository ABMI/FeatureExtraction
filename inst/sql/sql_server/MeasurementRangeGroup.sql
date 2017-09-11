-- Feature construction
SELECT 
	(CAST(measurement_concept_id AS BIGINT) * 10000) + (range_group * 1000) + @analysis_id AS covariate_id,
{@temporal} ? {
    time_id,
}	
{@aggregated} ? {
	COUNT(*) AS sum_value,
	COUNT(*) / (1.0 * (SELECT COUNT(*) FROM @cohort_table {@cohort_definition_id != -1} ? {WHERE cohort_definition_id = @cohort_definition_id})) AS average_value
} : {
	row_id,
	1 AS covariate_value 
}
INTO @covariate_table
FROM (
	SELECT measurement_concept_id,
		CASE 
			WHEN value_as_number < range_low THEN 1
			WHEN value_as_number > range_high THEN 3
			ELSE 2
		END AS range_group,		
{@temporal} ? {
		time_id,
}	
{@aggregated} ? {
		cohort.subject_id,
		cohort.cohort_start_date
} : {
		cohort.@row_id_field AS row_id
}
	FROM @cohort_table cohort
	INNER JOIN @cdm_database_schema.measurement
		ON cohort.subject_id = measurement.person_id
{@temporal} ? {
	INNER JOIN #time_period time_period
		ON measurement_date <= DATEADD(DAY, time_period.end_day, cohort.cohort_start_date)
		AND measurement_date >= DATEADD(DAY, time_period.start_day, cohort.cohort_start_date)
	WHERE measurement_concept_id != 0
} : {
	WHERE measurement_date <= DATEADD(DAY, @end_day, cohort.cohort_start_date)
{@start_day != 'anyTimePrior'} ? {				AND measurement_date >= DATEADD(DAY, @start_day, cohort.cohort_start_date)}
		AND measurement_concept_id != 0
}
		AND range_low IS NOT NULL
		AND range_high IS NOT NULL
{@excluded_concept_table != ''} ? {		AND measurement_concept_id NOT IN (SELECT id FROM @excluded_concept_table)}
{@included_concept_table != ''} ? {		AND measurement_concept_id IN (SELECT id FROM @included_concept_table)}
{@cohort_definition_id != -1} ? {		AND cohort.cohort_definition_id = @cohort_definition_id}
) by_row_id
{@included_cov_table != ''} ? {WHERE (CAST(measurement_concept_id AS BIGINT) * 10000) + (range_group * 1000) + @analysis_id IN (SELECT id FROM @included_cov_table)}
GROUP BY measurement_concept_id,
	range_group
{!@aggregated} ? {		
	,row_id
} 
{@temporal} ? {
    ,time_id
} 
;

-- Reference construction
INSERT INTO #cov_ref (
	covariate_id,
	covariate_name,
	analysis_id,
	concept_id
	)
SELECT covariate_id,
{@temporal} ? {
	CONCAT('measurement ', range_name, ': ', concept_id, '-', concept_name) AS covariate_name,
} : {
{@start_day == 'anyTimePrior'} ? {
	CONCAT('measurement ', range_name, ' during any time prior through @end_day days relative to index: ', concept_id, '-', concept_name) AS covariate_name,
} : {
	CONCAT('measurement ', range_name, ' during day @start_day through @end_day days relative to index: ', concept_id, '-', concept_name) AS covariate_name,
}
}
	@analysis_id AS analysis_id,
	concept_id
FROM (
	SELECT DISTINCT covariate_id
	FROM @covariate_table
	) t1
INNER JOIN @cdm_database_schema.concept
	ON concept_id = FLOOR(covariate_id / 10000.0)
INNER JOIN (
	SELECT 1 AS range_group, CAST('below normal range' AS VARCHAR(50)) AS range_name
	UNION ALL
	SELECT 2 AS range_group, CAST('within normal range' AS VARCHAR(50)) AS range_name
	UNION ALL
	SELECT 3 AS range_group, CAST('above normal range' AS VARCHAR(50)) AS range_name
) group_names
ON group_names.range_group = FLOOR(covariate_id / 1000.0) - (FLOOR(covariate_id / 10000.0) * 10);
	
INSERT INTO #analysis_ref (
	analysis_id,
	analysis_name,
	domain_id,
{!@temporal} ? {
	start_day,
	end_day,
}
	is_binary,
	missing_means_zero
	)
SELECT @analysis_id AS analysis_id,
	'@analysis_name' AS analysis_name,
	'@domain_id' AS domain_id,
{!@temporal} ? {
{@start_day == 'anyTimePrior'} ? {
	NULL AS start_day,
} : {
	@start_day AS start_day,
}
	@end_day AS end_day,
}
	'Y' AS is_binary,
	NULL AS missing_means_zero;

