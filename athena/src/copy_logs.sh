#!/bin/bash

echo "### check: aws access key ..."
aws s3 ls s3://$S3_BUCKET > /dev/null
if [ $? -ne 0 ]; then
    echo "### error: can't read bucket $S3_BUCKET" 1>&2
    exit 1
fi
echo "ok!"

s3_base="s3://$S3_BUCKET/motobrew_devops_test/access_log"

ls /tmp/logs | while read filename
do
    # partition key `dt` from file name
    # dt=YYYYMMDD
    dt=${filename:7:8}

    aws s3 cp /tmp/logs/$filename $s3_base/dt=$dt/
done
