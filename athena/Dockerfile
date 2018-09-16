FROM python:3.6

RUN pip install awscli boto3 docopt pytz datetime pystache

ADD src /tmp/src/

RUN chmod 755 /tmp/src/copy_logs.sh
