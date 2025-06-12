# Nessie CDC Lakehouse - Sequence Diagrams

## 🔄 **Primary Data Flow Sequence**

### **Real-time CDC Processing Pipeline**

```mermaid
sequenceDiagram
    participant App as Application
    participant PG as PostgreSQL
    participant DBZ as Debezium
    participant Kafka as Apache Kafka
    participant Flink as Apache Flink
    participant Nessie as Nessie Catalog
    participant Iceberg as Iceberg Tables
    participant MinIO as MinIO Storage
    participant Dremio as Dremio Query

    Note over App,Dremio: Real-time CDC Lakehouse Data Flow

    %% Initial Setup Phase
    App->>PG: INSERT/UPDATE/DELETE data
    PG->>PG: Write to WAL (Write-Ahead Log)
    Note over PG: wal_level=logical enabled for CDC

    %% CDC Capture Phase
    DBZ->>PG: Monitor WAL changes
    PG-->>DBZ: Stream WAL events
    DBZ->>DBZ: Transform to JSON CDC format
    DBZ->>Kafka: Publish CDC events
    Note over DBZ,Kafka: Topic: demographics_server.public.demographics

    %% Stream Processing Phase
    Flink->>Kafka: Consume CDC messages
    Note over Flink: Consumer group: flink-streaming
    Kafka-->>Flink: Stream CDC events
    Flink->>Flink: Parse JSON and apply transformations
    
    %% Catalog Integration Phase
    Flink->>Nessie: Request catalog connection
    Note over Flink,Nessie: catalog-impl=org.apache.iceberg.nessie.NessieCatalog
    Nessie-->>Flink: Catalog instance ready
    
    Flink->>Nessie: Create/update table schema
    Nessie->>Nessie: Git-like commit for schema changes
    Nessie-->>Flink: Schema commit confirmed
    
    %% Data Writing Phase
    Flink->>Iceberg: Append new data records
    Note over Flink,Iceberg: APPEND mode for streaming
    Iceberg->>MinIO: Write parquet files
    Note over Iceberg,MinIO: S3FileIO with AWS_REGION=us-east-1
    MinIO-->>Iceberg: Storage confirmation
    Iceberg-->>Flink: Write operation complete
    
    Flink->>Nessie: Commit data changes
    Nessie->>Nessie: Update branch with new snapshot
    Nessie-->>Flink: Data commit confirmed
    
    %% Query Phase
    Dremio->>Nessie: Query table metadata
    Nessie-->>Dremio: Return current snapshot info
    Dremio->>MinIO: Read parquet files
    MinIO-->>Dremio: Stream data for query
    Dremio->>Dremio: Execute SQL analytics
    
    Note over App,Dremio: End-to-end latency: < 10 seconds
```

---

## 🚀 **System Startup Sequence**

### **Container Orchestration and Service Dependencies**

```mermaid
sequenceDiagram
    participant User as User
    participant Docker as Docker Compose
    participant Network as data-lakehouse network
    participant PG as PostgreSQL
    participant MinIO as MinIO
    participant Kafka as Kafka
    participant Nessie as Nessie
    participant Flink as Flink Cluster
    participant DBZ as Debezium
    participant Scripts as Automation Scripts

    Note over User,Scripts: System Startup and Initialization

    %% Infrastructure Setup
    User->>Docker: docker compose up -d
    Docker->>Network: Create bridge network
    
    %% Core Services Startup
    Docker->>PG: Start PostgreSQL container
    Docker->>MinIO: Start MinIO S3 storage
    Docker->>Kafka: Start Kafka broker
    Docker->>Nessie: Start Nessie catalog
    
    %% Health Checks
    PG->>PG: Initialize demographics database
    MinIO->>MinIO: Create warehouse bucket
    Kafka->>Kafka: Auto-create topics enabled
    Nessie->>Nessie: Initialize Git repository
    
    %% Flink Cluster Startup
    Docker->>Flink: Start JobManager
    Docker->>Flink: Start TaskManager(s)
    Note over Flink: AWS_REGION=us-east-1 environment
    Flink->>Flink: Register available task slots
    
    %% CDC Components
    Docker->>DBZ: Start Debezium connector
    DBZ->>PG: Establish replication slot
    DBZ->>Kafka: Register CDC topic
    
    %% Pipeline Initialization
    User->>Scripts: ./start_continuous_cdc.sh
    Scripts->>Scripts: Source pipeline_config.env
    Scripts->>Flink: Submit CDC streaming job
    
    %% Job Deployment
    Flink->>Nessie: Initialize catalog connection
    Flink->>Kafka: Setup consumer groups
    Flink->>MinIO: Verify S3 connectivity
    
    Note over User,Scripts: All services operational - Ready for real-time CDC
```

---

## 🛠️ **Troubleshooting Sequence - AWS_REGION Issue**

### **Problem Diagnosis and Resolution**

```mermaid
sequenceDiagram
    participant User as User
    participant Flink as Flink Job
    participant S3Client as AWS S3Client
    participant Docker as Docker Container
    participant Fix as Resolution Process

    Note over User,Fix: AWS_REGION Issue Resolution Timeline

    %% Problem Detection
    User->>Flink: Submit CDC streaming job
    Flink->>S3Client: Initialize S3FileIO
    S3Client->>S3Client: Attempt region discovery
    S3Client-->>Flink: ERROR: Unable to load region
    Note over S3Client: DefaultAwsRegionProviderChain failed
    Flink-->>User: Job Status: FAILED
    
    %% Investigation Phase
    User->>Flink: Check job exceptions via REST API
    Flink-->>User: Stack trace with region error
    User->>Docker: Inspect container environment
    Docker-->>User: AWS_REGION not found
    
    %% Root Cause Analysis
    Note over User,Fix: Root Cause: Missing AWS_REGION environment variable
    
    %% Solution Implementation
    User->>Fix: Edit docker-compose.yml
    Fix->>Fix: Add AWS_REGION=us-east-1 to Flink services
    User->>Docker: docker compose down jobmanager taskmanager
    User->>Docker: docker compose up -d jobmanager taskmanager
    
    %% Verification
    Docker->>Flink: Restart with new environment
    User->>Docker: docker exec - verify AWS_REGION
    Docker-->>User: AWS_REGION=us-east-1 confirmed
    
    %% Success Validation
    User->>Flink: Resubmit CDC streaming job
    Flink->>S3Client: Initialize S3FileIO with region
    S3Client->>S3Client: Region successfully loaded
    S3Client-->>Flink: S3 client ready
    Flink-->>User: Job Status: RUNNING
    
    Note over User,Fix: Issue resolved - Full pipeline operational
```

---

## 📊 **Data Transformation Sequence**

### **CDC Event Processing and Schema Evolution**

```mermaid
sequenceDiagram
    participant Source as Source Table
    participant CDC as CDC Event
    participant Transform as Flink SQL
    participant Schema as Schema Registry
    participant Target as Iceberg Table

    Note over Source,Target: Data Transformation Pipeline

    %% Source Data Change
    Source->>CDC: Row change (INSERT/UPDATE/DELETE)
    CDC->>CDC: Capture change metadata
    Note over CDC: Include: operation, timestamp, before/after
    
    %% Event Structure
    CDC->>Transform: JSON CDC event
    Note over CDC,Transform: {"op":"c","ts_ms":...,"before":null,"after":{...}}
    
    %% Schema Validation
    Transform->>Schema: Validate event schema
    Schema->>Schema: Check field compatibility
    Schema-->>Transform: Schema validation passed
    
    %% Field Mapping
    Transform->>Transform: Map CDC fields to target schema
    Note over Transform: Handle: id→id, name→name, age→age, city→city
    Transform->>Transform: Add processing metadata
    Note over Transform: processing_time, event_time, operation_type
    
    %% Data Quality Checks
    Transform->>Transform: Apply data quality rules
    Note over Transform: Non-null constraints, data type validation
    
    %% Target Writing
    Transform->>Target: Append transformed record
    Target->>Target: Update table metadata
    Target->>Target: Create new snapshot
    Note over Target: Maintain schema evolution compatibility
    
    Note over Source,Target: Transformation complete with ACID guarantees
```

---

## 🔧 **Monitoring and Health Check Sequence**

### **System Health Validation Flow**

```mermaid
sequenceDiagram
    participant Admin as Administrator
    participant Script as Health Check Script
    participant Flink as Flink Cluster
    participant Kafka as Kafka Broker
    participant MinIO as MinIO Storage
    participant Nessie as Nessie Catalog
    participant Dashboard as Monitoring Dashboard

    Note over Admin,Dashboard: System Health Monitoring Sequence

    %% Health Check Initiation
    Admin->>Script: Execute ./test_fixed_cdc_pipeline.sh
    Script->>Script: Source pipeline_config.env
    
    %% Service Connectivity Tests
    Script->>Flink: test_flink() - Check JobManager
    Flink-->>Script: Response: Flink cluster healthy
    
    Script->>Kafka: test_kafka() - List topics
    Kafka-->>Script: Response: CDC topics available
    
    Script->>MinIO: test_minio() - List buckets
    MinIO-->>Script: Response: Warehouse bucket accessible
    
    Script->>Nessie: test_nessie() - API health
    Nessie-->>Script: Response: Catalog API operational
    
    %% Data Flow Validation
    Script->>Kafka: Check CDC message count
    Kafka-->>Script: Response: X messages in CDC topic
    
    Script->>Flink: Query running jobs status
    Flink-->>Script: Response: Y jobs running/finished
    
    Script->>MinIO: Verify recent file writes
    MinIO-->>Script: Response: Files written within threshold
    
    %% Dashboard Updates
    Script->>Dashboard: Update health status
    Dashboard->>Dashboard: Refresh monitoring metrics
    Dashboard-->>Admin: Visual health status display
    
    Note over Admin,Dashboard: All systems operational - Pipeline healthy
```

---

## 💡 **Key Sequence Patterns**

### **Critical Success Factors**

1. **Dependency Order**: PostgreSQL → Kafka → Flink → Nessie → MinIO
2. **Environment Setup**: AWS_REGION must be set before S3FileIO initialization
3. **Catalog Syntax**: Use `catalog-impl` not `catalog-type` for Nessie
4. **Consumer Groups**: Proper Kafka consumer group management for exactly-once processing
5. **Health Checks**: Sequential validation of each component before pipeline start

### **Error Recovery Patterns**

1. **Job Failure**: Flink checkpointing enables automatic restart from last consistent state
2. **Connection Loss**: Kafka consumer offset management ensures no data loss
3. **Storage Issues**: MinIO redundancy and Iceberg metadata versioning provide durability
4. **Schema Changes**: Nessie branching allows safe schema evolution with rollback capability

### **Performance Optimization**

1. **Parallel Processing**: Flink parallelism configuration matches available task slots
2. **Batch Optimization**: Iceberg commit interval balances latency vs. efficiency
3. **Network Efficiency**: Container-to-container communication via internal network
4. **Resource Management**: Docker resource limits prevent service interference

---

**🎯 Sequence Flow Summary**: Complete end-to-end real-time CDC pipeline with comprehensive monitoring, error handling, and performance optimization patterns. 