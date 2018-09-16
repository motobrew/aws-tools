SELECT
  uri
  , substr(time, 1, 10)  AS date
  , count(*) count
FROM
  {{ athena_db }}.access_log_view
GROUP BY
  substr(time, 1, 10), uri
ORDER BY
  uri, date
;