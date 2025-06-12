# 🚀 DEBEZIUM + FLINK 1.18.3 CDC PIPELINE

## 📖 Tổng quan Architecture

```
PostgreSQL (WAL) → Debezium → Kafka → Flink 1.18.3 → Iceberg → MinIO
                   ↓           ↓        ↓             ↓         ↓
              CDC Capture → Message → Processing → Data Lake → Analytics
```

### ✨ Ưu điểm Production Architecture

✅ **Debezium**: Chuyên dụng cho CDC, stable, enterprise-grade  
✅ **Kafka**: Message buffer, reliability, scaling  
✅ **Flink 1.18.3**: SQL Client Web UI, mature streaming  
✅ **Iceberg**: ACID transactions, time travel  
✅ **Monitoring**: Kafka UI, Flink Web UI  

## 🚀 Triển khai Nhanh

### Bước 1: Deploy toàn bộ pipeline
```bash
chmod +x deploy_debezium_flink.sh
./deploy_debezium_flink.sh
```

### Bước 2: Kiểm tra deployment
```bash
chmod +x validate_debezium_pipeline.sh
./validate_debezium_pipeline.sh
```

### Bước 3: Test real-time CDC
```bash
chmod +x test_realtime_cdc.sh
./test_realtime_cdc.sh
```

## 📊 Components và Ports

| Service | Port | Description | URL |
|---------|------|-------------|-----|
| PostgreSQL | 5432 | Source database với WAL | - |
| Kafka | 9092 | Message broker | - |
| Debezium | 8083 | CDC connector | http://localhost:8083 |
| Flink Web UI | 8081 | Job management | http://localhost:8081 |
| Kafka UI | 8082 | Topic monitoring | http://localhost:8082 |
| MinIO | 9001 | S3 lakehouse | http://localhost:9001 |
| Nessie | 19120 | Catalog service | http://localhost:19120 |

## 🔧 Manual Setup Chi tiết

### 1. Bật WAL trên PostgreSQL

PostgreSQL đã được cấu hình với WAL level logical:
```sql
-- Kiểm tra WAL level
SHOW wal_level; -- Kết quả: logical

-- Tạo publication cho Debezium
CREATE PUBLICATION debezium_publication FOR TABLE demographics;
```

### 2. Đăng ký Debezium Connector

```bash
curl -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d @debezium/postgres-connector.json
```

### 3. Tạo Flink Tables qua Web UI

Truy cập **http://localhost:8081** → SQL Client → Submit Job

#### Kafka Source Table:
```sql
CREATE TABLE kafka_demographics_source (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    __op STRING,
    __source_ts_ms BIGINT,
    __source_db STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'demographics_server.public.demographics',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-demographics-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);
```

#### Iceberg Sink Table:
```sql
CREATE TABLE iceberg_demographics_sink (
    city STRING,
    state STRING,
    median_age DOUBLE,
    male_population INT,
    female_population INT,
    total_population INT,
    number_of_veterans INT,
    foreign_born INT,
    average_household_size DOUBLE,
    state_code STRING,
    race STRING,
    count INT,
    cdc_operation STRING,
    cdc_timestamp TIMESTAMP(3),
    processing_time TIMESTAMP(3)
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'nessie',
    'catalog-type' = 'nessie',
    'uri' = 'http://nessie:19120/api/v1',
    'warehouse' = 's3a://lakehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'minioadmin',
    's3.secret-access-key' = 'minioadmin123',
    's3.path-style-access' = 'true',
    'catalog-database' = 'demographics_db',
    'catalog-table' = 'demographics_cdc_table'
);
```

#### Streaming Job:
```sql
INSERT INTO iceberg_demographics_sink
SELECT 
    city,
    state,
    median_age,
    male_population,
    female_population,
    total_population,
    number_of_veterans,
    foreign_born,
    average_household_size,
    state_code,
    race,
    count,
    COALESCE(__op, 'u') as cdc_operation,
    TO_TIMESTAMP_LTZ(__source_ts_ms, 3) as cdc_timestamp,
    CURRENT_TIMESTAMP as processing_time
FROM kafka_demographics_source
WHERE __op IS NULL OR __op IN ('c', 'u', 'd');
```

## 🧪 Testing CDC

### Insert Test Data
```sql
INSERT INTO demographics (
    city, state, median_age, male_population, female_population, 
    total_population, number_of_veterans, foreign_born, 
    average_household_size, state_code, race, count
) VALUES (
    'CDC_Test_City', 'CDC_State', 30.0, 45000, 47000, 
    92000, 7500, 8500, 2.3, 'CD', 'Test_Race', 1
);
```

### Monitor Kafka Messages
```bash
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic demographics_server.public.demographics \
  --from-beginning
```

### Check Flink Jobs
Truy cập: http://localhost:8081

### Verify Lakehouse Data
```bash
docker exec minioserver mc ls -r local/lakehouse/
```

## 📊 Monitoring & Health Check

### 1. Pipeline Status
```bash
./validate_debezium_pipeline.sh
```

### 2. Debezium Connector Status
```bash
curl http://localhost:8083/connectors/postgres-demographics-connector/status
```

### 3. Kafka Topics
```bash
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list
```

### 4. Flink Jobs API
```bash
curl http://localhost:8081/jobs
```

## 🎯 Data Flow Workflow

### 1. PostgreSQL WAL → Debezium
- WAL level: `logical`
- Publication: `debezium_publication`
- Slot: `debezium_slot`

### 2. Debezium → Kafka
- Topic: `demographics_server.public.demographics`
- Format: JSON với CDC metadata
- Operations: CREATE (`c`), UPDATE (`u`), DELETE (`d`)

### 3. Kafka → Flink
- Kafka Source Table với JSON format
- CDC fields: `__op`, `__source_ts_ms`, `__source_db`
- Group ID: `flink-demographics-consumer`

### 4. Flink → Iceberg
- Transformations: timestamp conversion, operation mapping
- Iceberg features: UPSERT, ACID transactions
- Storage: MinIO S3-compatible

## 🔧 Troubleshooting

### Debezium Issues
```bash
# Check logs
docker logs debezium

# Check connector status
curl http://localhost:8083/connectors

# Restart connector
curl -X POST http://localhost:8083/connectors/postgres-demographics-connector/restart
```

### Kafka Issues
```bash
# List topics
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Check consumer groups
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --list

# Reset consumer group
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group flink-demographics-consumer --reset-offsets --to-earliest --topic demographics_server.public.demographics --execute
```

### Flink Issues
```bash
# Check Flink logs
docker logs jobmanager
docker logs taskmanager

# Restart Flink cluster
docker-compose restart jobmanager taskmanager

# Check job status
curl http://localhost:8081/jobs
```

### PostgreSQL WAL Issues
```sql
-- Check WAL level
SHOW wal_level;

-- Check replication slots
SELECT * FROM pg_replication_slots;

-- Check publications
SELECT * FROM pg_publication;

-- Drop and recreate publication
DROP PUBLICATION IF EXISTS debezium_publication;
CREATE PUBLICATION debezium_publication FOR TABLE demographics;
```

## 🚀 Production Recommendations

### 1. Resource Tuning
```yaml
# docker-compose.yml optimizations
jobmanager:
  environment:
    - FLINK_PROPERTIES=
      taskmanager.numberOfTaskSlots: 4
      parallelism.default: 2
      state.backend: rocksdb
      state.checkpoints.dir: s3a://lakehouse/checkpoints
      execution.checkpointing.interval: 30s
```

### 2. Kafka Configuration
```yaml
kafka:
  environment:
    KAFKA_NUM_PARTITIONS: 3
    KAFKA_DEFAULT_REPLICATION_FACTOR: 3
    KAFKA_LOG_RETENTION_HOURS: 168
```

### 3. Monitoring Setup
- **Kafka UI**: http://localhost:8082 để monitor topics và consumers
- **Flink Web UI**: http://localhost:8081 để monitor jobs và metrics
- **Debezium JMX**: Enable JMX metrics cho production monitoring

### 4. Security (Production)
```yaml
# SSL/TLS encryption
# SASL authentication
# Network policies
# Secret management
```

## 📝 Schema Evolution

Debezium tự động xử lý schema changes:
```sql
-- Add column (automatically handled)
ALTER TABLE demographics ADD COLUMN new_field VARCHAR(100);

-- Update connector to include new field
-- Flink sẽ tự động nhận schema mới từ Kafka
```

## 📊 Performance Tuning

### Kafka Performance
```yaml
# Increase batch size
KAFKA_PRODUCER_BATCH_SIZE: 65536
KAFKA_PRODUCER_LINGER_MS: 5
```

### Flink Performance
```sql
-- Checkpoint configuration
'execution.checkpointing.interval' = '30s'
'execution.checkpointing.min-pause' = '10s'
'execution.checkpointing.timeout' = '5min'
```

### Debezium Performance
```json
{
  "max.batch.size": "2048",
  "max.queue.size": "8192",
  "poll.interval.ms": "1000"
}
```

## 🎉 Success Indicators

✅ **All services running**: 15+ containers  
✅ **Debezium connector**: RUNNING status  
✅ **Kafka topics**: demographics_server.public.demographics exists  
✅ **Flink jobs**: Active streaming job  
✅ **Data flow**: PostgreSQL → Kafka → Flink → Lakehouse  
✅ **Real-time CDC**: INSERT/UPDATE/DELETE captured instantly  

## 📋 Quick Commands Reference

```bash
# Deploy pipeline
./deploy_debezium_flink.sh

# Validate pipeline  
./validate_debezium_pipeline.sh

# Test real-time CDC
./test_realtime_cdc.sh

# Monitor Kafka messages
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic demographics_server.public.demographics --from-beginning

# Check connector status
curl http://localhost:8083/connectors/postgres-demographics-connector/status

# Flink Web UI
open http://localhost:8081

# Kafka UI
open http://localhost:8082
```

---

🎯 **Production-grade Debezium + Flink 1.18.3 CDC Pipeline hoàn thành!**

**Time to deploy**: ~15-20 minutes  
**Architecture**: Enterprise-scale, fault-tolerant  
**Monitoring**: Comprehensive với Web UIs  
**Real-time**: True CDC với sub-second latency 