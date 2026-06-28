# Makefile — helpers สำหรับจัดการ PostgreSQL ที่รันใน Docker (minecraft-server/docker-compose.yml)
# ค่าทั้งหมดต้องตรงกับ docker-compose.yml: container=postgres_db, user=root, db=mrfermz

COMPOSE_FILE := minecraft-server/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_FILE)
DB_CONTAINER := postgres_db
DB_USER      := root
DB_NAME      := mrfermz

.PHONY: db-up db-down db-reset db-hard-reset db-psql db-wait

## เปิด postgres (ถ้ายังไม่รัน)
db-up:
	$(COMPOSE) up -d postgres

## ปิด postgres (ไม่ลบ volume)
db-down:
	$(COMPOSE) stop postgres

## รอจน postgres พร้อมรับ connection
db-wait:
	@echo "waiting for postgres..."
	@until docker exec $(DB_CONTAINER) pg_isready -U $(DB_USER) -d $(DB_NAME) >/dev/null 2>&1; do \
		sleep 1; \
	done
	@echo "postgres is ready"

## reset: drop แล้วสร้าง database ใหม่ (เร็ว, เก็บ container/volume ไว้)
db-reset: db-up db-wait
	@echo "resetting database '$(DB_NAME)'..."
	@docker exec $(DB_CONTAINER) psql -U $(DB_USER) -d postgres -v ON_ERROR_STOP=1 \
		-c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$(DB_NAME)' AND pid <> pg_backend_pid();" \
		-c "DROP DATABASE IF EXISTS $(DB_NAME);" \
		-c "CREATE DATABASE $(DB_NAME) OWNER $(DB_USER);"
	@echo "database '$(DB_NAME)' reset done"

## hard reset: ลบ volume ทิ้งทั้งก้อนแล้ว start ใหม่ (ล้างทุกอย่างจริง ๆ)
db-hard-reset:
	$(COMPOSE) down -v
	$(COMPOSE) up -d postgres
	@$(MAKE) db-wait

## เปิด psql shell เข้า database
db-psql:
	docker exec -it $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME)
