WITH daily_rank AS (
SELECT
  substr(time, 1, 10) date
  , rank() OVER (PARTITION BY substr(time, 1, 10) ORDER BY reqtime DESC) AS rank
  , *
FROM
  {{ athena_db }}.access_log_view
)
SELECT
  *
FROM
  daily_rank
WHERE
  rank <= 10
ORDER BY date, rank
;