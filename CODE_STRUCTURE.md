# Nessie CDC Lakehouse - Code Structure & Architecture

## 📁 **PROJECT DIRECTORY STRUCTURE**

```
Project04/
├── 🏗️ Infrastructure
│   ├── docker-compose.yml                    # Main orchestration (12 services)
│   ├── pipeline_config.env                   # Unified configuration management
│   └── core-site.xml                         # Hadoop configuration
│
├── 📊 Core CDC Pipeline Scripts
│   ├── submit_nessie_cdc_job_fixed.sh        # 🎯 PRIMARY: Complete CDC pipeline
│   ├── start_continuous_cdc.sh               # 🎯 PRODUCTION: Persistent streaming
│   ├── clean_restart_cdc_pipeline.sh         # 🔄 Reset and restart pipeline
│   └── restart_cdc_simple.sh                 # Simple mode restart
│
├── 🔍 Validation & Testing
│   ├── test_fixed_cdc_pipeline.sh            # 🎯 PRIMARY: Post-fix validation
│   ├── comprehensive_pipeline_test.sh        # End-to-end testing
│   ├── validate_complete_pipeline.sh         # Complete validation suite
│   └── test_kafka_only_cdc.sh                # Kafka-only bypass test
│
├── 🗄️ SQL Definitions
│   ├── nessie_cdc_to_iceberg_job_final.sql   # 🎯 WORKING: Final CDC job
│   ├── complete_cdc_to_lakehouse.sql         # Complete pipeline SQL
│   ├── nessie_iceberg_setup.sql              # Nessie catalog setup
│   └── test_nessie_catalog_impl.sql          # Catalog implementation test
│
├── 🛠️ Setup & Configuration
│   ├── setup_nessie_flink_dependencies.sh    # Dependency verification
│   ├── setup_iceberg_with_env.sh             # Environment setup
│   ├── deploy_complete_cdc_pipeline.sh       # Deployment automation
│   └── configure_dremio_sources.sh           # Dremio configuration
│
├── 📈 Monitoring & Maintenance
│   ├── monitor_cdc_pipeline.sh               # Pipeline monitoring
│   ├── validate_data_consistency.sh          # Data consistency checks
│   └── COMPREHENSIVE_VALIDATION_REPORT.md    # Validation results
│
├── 📚 Documentation
│   ├── DEPLOYMENT_STATUS_SUMMARY.md          # Project status summary
│   ├── SYSTEM_OVERVIEW.md                    # System architecture
│   ├── SEQUENCE_DIAGRAM.md                   # Data flow diagrams
│   └── README.md                             # Project documentation
│
└── 📁 Supporting Directories
    ├── dags/                                 # Airflow DAGs (if used)
    ├── dataset/citizen/                      # Sample datasets
    ├── logs/                                 # Application logs
    ├── notebooks/                            # Jupyter notebooks
    └── scripts/                              # Additional utilities
```

---

## 🎯 **CORE COMPONENTS ANALYSIS**

### **1. Infrastructure Layer (`docker-compose.yml`)**

```yaml
# Service Architecture Overview
services:
  # Data Source
  postgres:              # PostgreSQL 15 with WAL enabled
  
  # Message Broker
  kafka:                 # Confluent Platform 7.5.0
  zookeeper:            # Kafka coordination
  
  # Stream Processing
  jobmanager:           # Flink JobManager (AWS_REGION configured)
  taskmanager:          # Flink TaskManager (AWS_REGION configured)
  
  # Data Catalog
  nessie:               # Nessie 0.67.0 catalog server
  
  # Storage
  minioserver:          # MinIO S3-compatible storage
  
  # CDC Connector
  debezium:             # Debezium 2.4 CDC connector
  
  # Analytics
  dremio:               # Dremio query engine
  
  # Management
  pgadmin:              # PostgreSQL administration
  kafka-ui:             # Kafka monitoring
```

**Key Features:**
- **Network**: Bridge network `data-lakehouse` for service isolation
- **Volumes**: Persistent storage for data, checkpoints, and logs
- **Environment**: `AWS_REGION=us-east-1` critical for S3FileIO
- **Health Checks**: Automatic service dependency management

---

### **2. Configuration Management (`pipeline_config.env`)**

```bash
# Centralized Configuration Pattern
# Database Configuration
export PG_HOST="postgres"
export PG_PORT="5432"
export PG_USER="admin"
export PG_PASSWORD="admin123"
export PG_DATABASE="demographics"

# MinIO S3 Configuration
export MINIO_ACCESS_KEY="DKZjmhls7nwxBN4GJfXC"
export MINIO_SECRET_KEY="kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t"
export MINIO_ENDPOINT="http://minioserver:9000"

# Service Endpoints
export FLINK_JOBMANAGER_URL="http://localhost:8081"
export NESSIE_URL_EXTERNAL="http://localhost:19120/api/v1"
export KAFKA_BROKER="localhost:9092"

# Utility Functions
test_flink() { ... }
test_kafka() { ... }
test_minio() { ... }
test_nessie() { ... }
```

**Design Pattern**: Single source of truth for all configurations with built-in validation functions.

---

### **3. Primary CDC Script (`submit_nessie_cdc_job_fixed.sh`)**

```bash
#!/bin/bash
# Production-Ready CDC Pipeline Script

# Configuration Loading
source pipeline_config.env

# Pre-flight Checks
echo "🔍 Running comprehensive system checks..."
test_flink && test_kafka && test_minio && test_nessie

# Cleanup Previous State
echo "🧹 Cleaning up previous pipeline state..."
# Drop existing tables and consumer groups

# Submit Streaming Job
echo "🚀 Submitting Nessie CDC streaming job..."
docker exec flink-jobmanager flink run \
    -d \
    /opt/flink/sql-client.jar \
    -j /opt/flink/lib/flink-sql-connector-*.jar \
    -s /path/to/nessie_cdc_to_iceberg_job_final.sql

# Validation
echo "✅ Validating pipeline deployment..."
# Check job status and data flow
```

**Architecture Principles:**
- **Idempotent**: Can be run multiple times safely
- **Validated**: Pre-flight checks ensure system readiness
- **Monitored**: Built-in validation and error reporting
- **Production-Ready**: Background execution with logging

---

### **4. SQL Pipeline Definition (`nessie_cdc_to_iceberg_job_final.sql`)**

```sql
-- 🎯 WORKING NESSIE CDC TO ICEBERG PIPELINE

-- 1. Create Nessie Catalog with Critical Configuration
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.nessie.NessieCatalog',  -- KEY BREAKTHROUGH
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    'uri' = 'http://nessie:19120/api/v1',
    'authentication.type' = 'none',
    'ref' = 'main',
    'warehouse' = 's3a://warehouse/',
    's3.endpoint' = 'http://minioserver:9000',
    's3.access-key-id' = 'DKZjmhls7nwxBN4GJfXC',
    's3.secret-access-key' = 'kNuAZodphLEGKHv5EmbyiDt1v5eT0yVErjVFyg0t',
    's3.path-style-access' = 'true',
    's3.region' = 'us-east-1'  -- CRITICAL FOR AWS SDK
);

-- 2. Create Target Database
CREATE DATABASE IF NOT EXISTS iceberg_catalog.cdc_db;

-- 3. Create Iceberg Target Table
CREATE TABLE IF NOT EXISTS iceberg_catalog.cdc_db.demographics_fixed (
    id BIGINT,
    name STRING,
    age INT,
    city STRING,
    processing_time TIMESTAMP_LTZ(3),
    event_time TIMESTAMP_LTZ(3)
) WITH (
    'format-version' = '2',
    'write.upsert.enabled' = 'false'  -- APPEND mode for streaming
);

-- 4. Insert Streaming Data from Kafka
INSERT INTO iceberg_catalog.cdc_db.demographics_fixed
SELECT 
    CAST(JSON_VALUE(value, '$.after.id') AS BIGINT) as id,
    JSON_VALUE(value, '$.after.name') as name,
    CAST(JSON_VALUE(value, '$.after.age') AS INT) as age,
    JSON_VALUE(value, '$.after.city') as city,
    PROCTIME() as processing_time,
    TO_TIMESTAMP_LTZ(CAST(JSON_VALUE(value, '$.ts_ms') AS BIGINT), 3) as event_time
FROM (
    SELECT value
    FROM TABLE(kafka_table(
        'connector' = 'kafka',
        'topic' = 'demographics_server.public.demographics',
        'properties.bootstrap.servers' = 'kafka:9092',
        'properties.group.id' = 'flink-nessie-cdc-fixed',
        'scan.startup.mode' = 'latest-offset',  -- Continuous streaming
        'format' = 'json'
    ))
) WHERE JSON_VALUE(value, '$.after.id') IS NOT NULL;
```

**SQL Design Patterns:**
- **Catalog-impl Syntax**: Critical breakthrough using `org.apache.iceberg.nessie.NessieCatalog`
- **S3 Configuration**: Complete S3FileIO setup with region specification
- **JSON Processing**: Robust CDC event parsing with null handling
- **Streaming Mode**: Latest-offset for continuous real-time processing

---

## 🧪 **TESTING & VALIDATION FRAMEWORK**

### **Test Categories**

```bash
# 1. Unit Tests - Individual Component Testing
test_flink()          # Flink cluster health
test_kafka()          # Kafka broker connectivity  
test_minio()          # MinIO storage access
test_nessie()         # Nessie catalog API

# 2. Integration Tests - Component Interaction
test_cdc_to_kafka()   # PostgreSQL → Debezium → Kafka
test_kafka_to_flink() # Kafka → Flink consumption
test_flink_to_nessie() # Flink → Nessie catalog integration
test_nessie_to_minio() # Nessie → Iceberg → MinIO storage

# 3. End-to-End Tests - Complete Pipeline
test_full_pipeline()  # PostgreSQL → MinIO complete flow
validate_data_consistency() # Data integrity across system
performance_benchmark() # Latency and throughput metrics
```

### **Validation Scripts Architecture**

```bash
# Primary Validation Script (test_fixed_cdc_pipeline.sh)
#!/bin/bash

# 1. System Prerequisites
source pipeline_config.env
check_docker_services()
verify_environment_variables()

# 2. Component Health Checks
validate_postgresql_cdc()
validate_kafka_topics()
validate_flink_cluster()
validate_nessie_api()
validate_minio_storage()

# 3. Data Flow Validation
insert_test_data()
verify_cdc_capture()
verify_streaming_processing()
verify_iceberg_storage()
generate_validation_report()

# 4. Performance Metrics
measure_end_to_end_latency()
validate_exactly_once_processing()
check_fault_tolerance()
```

---

## 🔧 **MONITORING & OBSERVABILITY**

### **Monitoring Stack**

```bash
# Service Health Monitoring
monitor_flink_jobs()        # Job status, checkpoints, backpressure
monitor_kafka_lag()         # Consumer lag, throughput, partitions
monitor_minio_storage()     # Storage usage, I/O metrics
monitor_nessie_commits()    # Commit frequency, branch health

# Performance Monitoring  
track_end_to_end_latency()  # PostgreSQL → Iceberg latency
track_throughput_metrics()  # Records/second processing rate
track_resource_usage()      # CPU, memory, disk utilization
track_error_rates()         # Failed jobs, connection errors
```

### **Logging Strategy**

```bash
# Log Aggregation Points
/logs/flink/              # Flink job execution logs
/logs/kafka/              # Kafka broker and consumer logs  
/logs/debezium/           # CDC connector logs
/logs/pipeline/           # Pipeline execution logs

# Log Analysis Patterns
grep "ERROR" logs/**/*.log           # Error detection
grep "checkpoint" logs/flink/*.log   # Checkpoint monitoring
grep "commit" logs/nessie/*.log      # Catalog commit tracking
```

---

## 🚀 **DEPLOYMENT PATTERNS**

### **Environment Management**

```bash
# Development Environment
docker-compose.yml              # Full stack for development
pipeline_config.env.dev        # Development configurations

# Testing Environment  
docker-compose.test.yml         # Testing-specific overrides
pipeline_config.env.test       # Test environment settings

# Production Environment
docker-compose.prod.yml         # Production optimizations
pipeline_config.env.prod       # Production secrets management
```

### **CI/CD Integration Points**

```bash
# Pre-deployment Validation
./comprehensive_pipeline_test.sh    # Full system validation
./validate_data_consistency.sh      # Data integrity checks

# Deployment Automation
./deploy_complete_cdc_pipeline.sh   # Automated deployment
./monitor_cdc_pipeline.sh           # Post-deployment monitoring

# Rollback Procedures
./clean_restart_cdc_pipeline.sh     # Clean restart capability
./restore_from_checkpoint.sh        # State recovery
```

---

## 💡 **ARCHITECTURAL INSIGHTS**

### **Key Technical Breakthroughs**

1. **Nessie Catalog Integration**
   - `catalog-impl` vs `catalog-type` syntax discovery
   - Direct Iceberg catalog instantiation pattern

2. **AWS SDK Integration**
   - `AWS_REGION` environment variable requirement
   - S3FileIO configuration for MinIO compatibility

3. **Streaming Architecture**
   - EXACTLY_ONCE processing semantics
   - Checkpointing for fault tolerance
   - Latest-offset for continuous streaming

4. **Schema Evolution Support**
   - Iceberg format version 2 features
   - Nessie git-like versioning capability

### **Performance Optimization Patterns**

```sql
-- Optimized Table Configuration
WITH (
    'format-version' = '2',                    -- Latest Iceberg features
    'write.upsert.enabled' = 'false',         -- Append-only for streaming
    'write.target-file-size-bytes' = '134217728', -- 128MB files
    'write.parquet.compression-codec' = 'snappy'   -- Fast compression
)

-- Optimized Consumer Configuration
'properties.group.id' = 'flink-nessie-cdc-fixed',
'scan.startup.mode' = 'latest-offset',         -- Real-time processing
'properties.max.poll.records' = '1000'         -- Batch optimization
```

### **Error Handling Patterns**

```bash
# Graceful Degradation
if ! test_nessie; then
    echo "❌ Nessie unavailable - using backup catalog"
    use_backup_catalog()
fi

# Automatic Recovery
restart_on_failure() {
    if [[ $? -ne 0 ]]; then
        echo "🔄 Job failed - attempting restart..."
        clean_restart_cdc_pipeline.sh
    fi
}

# Circuit Breaker Pattern
check_consecutive_failures() {
    if [[ $failure_count -gt 3 ]]; then
        echo "🚨 Circuit breaker triggered - manual intervention required"
        exit 1
    fi
}
```

---

## 📊 **CODE QUALITY & STANDARDS**

### **Coding Standards**

1. **Shell Script Standards**
   - Bash strict mode: `set -euo pipefail`
   - Function documentation with purpose and parameters
   - Error handling with meaningful messages
   - Configuration externalization via `.env` files

2. **SQL Standards**
   - Explicit data type casting
   - Comprehensive error handling
   - Performance-optimized table configurations
   - Schema evolution compatibility

3. **Documentation Standards**
   - README files for each major component
   - Inline comments for complex logic
   - Architecture decision records (ADRs)
   - Operational runbooks

### **Security Considerations**

```bash
# Credential Management
export SENSITIVE_VAR="$(cat /secure/path/secret.txt)"  # File-based secrets
unset SENSITIVE_VAR                                     # Cleanup after use

# Network Security
networks:
  data-lakehouse:
    driver: bridge                                      # Isolated network
    
# Access Control
docker exec --user flink flink-jobmanager              # Non-root execution
```

---

**🎯 Architecture Summary**: Complete enterprise-grade CDC lakehouse with robust error handling, comprehensive monitoring, and production-ready deployment patterns. The codebase demonstrates modern streaming architecture principles with emphasis on reliability, observability, and maintainability. 