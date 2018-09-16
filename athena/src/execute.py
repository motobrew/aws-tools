#!/usr/bin/env python3
# -*- coding: utf-8 -*-
__doc__ = """
Overview:
    Job Executer on Amazon Athena
    This executes DDL/SQL and shows its result.

Usage:
    {f} --query <query_path> [--dry-run]
    {f} -h|--help

Options:
    --query <query_path>    query file path
    --dry-run               dry run
    -h --help               show this screen and exit.

""".format(f=__file__)

import os
import sys
import boto3
from docopt import docopt
from pytz import timezone
from time import sleep
import datetime as dt
import pystache
from urllib.parse import urlparse

s3_bucket = os.environ['S3_BUCKET']
athena_db = os.environ['ATHENA_DB']

output_location = 's3://' + s3_bucket + '/motobrew_devops_test/athena_results/'
schema_file = ''
dry_run = False
athena_client = None
query_result_path = ''

def perse():
    global schema_file, dry_run

    args = docopt(__doc__)

    if args['--query']:
        schema_file = args['--query']

    if args['--dry-run']:
        dry_run = args['--dry-run']

def build_query():
    f = open(schema_file, 'r')
    query_base = f.read()
    f.close()

    return pystache.render(
        query_base,
        {
            's3_bucket': s3_bucket,
            'S3_BUCKET': s3_bucket,
            'athena_db': athena_db,
            'ATHENA_DB': athena_db
        })

def exec_query(query):
    if dry_run:
        logger("DRY RUN:")
        print(query)
        return False

    logger('execute query:')
    print(query)
    try:
        response = athena_client.start_query_execution(
            QueryString=query,
            QueryExecutionContext={
                'Database': athena_db
            },
            ResultConfiguration={
                'OutputLocation': output_location
            }
        )
    except Exception as e:
        print("### ERROR: {0}".format(e))
        sys.exit(1)

    execution_id = response['QueryExecutionId']
    return wait_job_state(execution_id)

def wait_job_state(execution_id):
    global query_result_path

    logger("wait query execution:")
    print("checking job state .", flush=True, end="")

    total_time = 0
    interval = 1
    max_timeout = 300

    while total_time < max_timeout:
        response = athena_client.get_query_execution(
          QueryExecutionId=execution_id
        )

        state = response['QueryExecution']['Status']['State']
        if state == 'SUCCEEDED':
            print(state)
            query_result_path = response['QueryExecution']['ResultConfiguration']['OutputLocation']
            return True
        elif state in {'CANCELLED', 'FAILED'}:
            print(state)
            logger("WARNING: Job State is [{0}]".format(state))
            return False
        else:
            # state is 'SUBMITTED' or 'RUNNING'
            print('.', flush=True, end='')

        sleep(interval)
        total_time += interval

    print("timeout!")
    return False

def show_query_result():
    logger("query result:")

    s3 = boto3.resource('s3')
    s3_key = urlparse(query_result_path).path.lstrip('/')

    obj = s3.Object(s3_bucket, s3_key)
    print(obj.get()['Body'].read().decode('utf-8'))

def main():
    global athena_client

    perse()
    athena_client = boto3.client('athena', region_name='ap-northeast-1')

    query = build_query()
    if exec_query(query):
        show_query_result()
        print("# query result: " + query_result_path)

def logger(message):
    print("### {0}: {1}".format(dt.datetime.now(timezone('UTC')).strftime('%Y-%m-%d %H:%M:%S'), message))

if __name__ == '__main__':
    main()
