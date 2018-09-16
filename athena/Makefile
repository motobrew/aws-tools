
LOGS_DIR=`pwd`/logs
ATHENA_DB=motobrew_devops_test
IMAGE=motobrew/devopstest
TAG=0.1

DOCKER_RUN=docker run \
	--env S3_BUCKET=$$S3_BUCKET \
	--env AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
	--env AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
	--env ATHENA_DB=$(ATHENA_DB) \
	-v $(LOGS_DIR):/tmp/logs \
	-it $(IMAGE):$(TAG)

all: build init sql

init: copy_logs create_db create_table repair_table create_view

sql: uri_count top10_reqtime

clean: drop_db

build:
	docker build -t $(IMAGE):$(TAG) .

run:
	$(DOCKER_RUN) bash

copy_logs:
	$(DOCKER_RUN) /tmp/src/copy_logs.sh

create_db:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/create_database.ddl

create_table:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/create_table.ddl

repair_table:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/repair_table.ddl

create_view:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/create_view.ddl

uri_count:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/uri_count.sql

top10_reqtime:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/top10_reqtime.sql

drop_db:
	$(DOCKER_RUN) python /tmp/src/execute.py --query /tmp/src/queries/drop_database.ddl

