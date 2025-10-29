# Database configuration
DB_NAME ?= wood-db
DB_TYPE ?= postgres
DB_USER ?= postgres
DB_PWD  ?= mysecretpassword
IP      ?= 127.0.0.1

# Postgres connection string
PSQLURL ?= $(DB_TYPE)://$(DB_USER):$(DB_PWD)@$(IP):5432/$(DB_NAME)

# sqlc config file
SQLC_YAML ?= ./backend/sqlc.yaml

# Container & volume
CONTAINER_NAME = wood-db
VOLUME_NAME    = wood-pgdata

.PHONY: postgresup postgresdown psql createdb teardown_recreate generate logs resetdb

postgresup:
	docker run --name $(CONTAINER_NAME) \
		-v $(VOLUME_NAME):/var/lib/postgresql/data \
		-v $(PWD):/usr/share/wood \
		-e POSTGRES_PASSWORD=$(DB_PWD) \
		-e POSTGRES_DB=$(DB_NAME) \
		-p 5432:5432 -d postgres:15

postgresdown:
	docker stop $(CONTAINER_NAME) || true && \
	docker rm $(CONTAINER_NAME) || true

psql:
	docker exec -it $(CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME)

createdb:
	docker exec -it $(CONTAINER_NAME) \
		psql -U $(DB_USER) -d $(DB_NAME) \
		-f /usr/share/wood/backend/schema/schema.sql

teardown_recreate: postgresdown postgresup
	sleep 5
	$(MAKE) createdb

generate:
	@echo "Generating Go models with sqlc..."
	sqlc generate -f $(SQLC_YAML)

logs:
	docker logs -f $(CONTAINER_NAME)

start:
	docker start $(CONTAINER_NAME)

resetdb: postgresdown
	docker volume rm $(VOLUME_NAME) || true
	$(MAKE) postgresup
	sleep 5
	$(MAKE) createdb

deletedb: postgresdown
	docker volume rm $(VOLUME_NAME) || true