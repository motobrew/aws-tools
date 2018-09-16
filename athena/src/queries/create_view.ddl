CREATE OR REPLACE VIEW {{ athena_db }}.access_log_view AS
SELECT
  record['method'] AS method
  , record['level'] AS level
  , record['reqtime'] AS reqtime
  , record['time'] AS time
  , record['id'] AS id
  , record['uri'] AS uri
  , dt
FROM {{ athena_db }}."access_log"
;