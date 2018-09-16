CREATE EXTERNAL TABLE IF NOT EXISTS
  access_log (
  record map<string,string>
)
PARTITIONED BY (dt string)
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY '\n'
  COLLECTION ITEMS TERMINATED BY '\t'
  MAP KEYS TERMINATED BY ':'
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://{{ s3_bucket }}/motobrew_devopstest/access_log/'
;
