# 🚀 Data Lakehouse Deployment Guide với CDC

## Tổng Quan

Hướng dẫn này sẽ triển khai một hệ thống Data Lakehouse hoàn chỉnh với Change Data Capture (CDC) từ PostgreSQL đến Apache Iceberg thông qua Apache Flink.

## Kiến Trúc Hệ Thống

```
PostgreSQL (WAL enabled) → Flink CDC → Apache Iceberg → MinIO (S3)
                                   ↓
                                 Nessie (Catalog)
                                   ↓
                            Dremio (Query Engine)
                                   ↓
                          Superset (Visualization)
```

## Chuẩn Bị

### Yêu Cầu Hệ Thống
- Docker & Docker Compose
- RAM: tối thiểu 8GB (khuyến nghị 16GB)
- Disk: tối thiểu 20GB free space
- CPU: tối thiểu 4 cores

### Files Được Tạo
1. `init.sql/init.sql` - Cấu hình PostgreSQL với WAL và CDC
2. `flink/Dockerfile` - Custom Flink image với connectors
3. `flink/flink-conf.yaml` - Cấu hình Flink
4. `postgres_to_iceberg.sql` - Pipeline SQL
5. `deploy.sh` - Script deployment tự động
6. `test-cdc.sh` - Script test CDC
7. `dags/cdc_pipeline_dag.py` - Airflow DAG

## Bước 1: Chuẩn Bị Deployment

```bash
# Cấp quyền execute cho scripts
chmod +x deploy.sh test-cdc.sh

# Kiểm tra Docker
docker --version
docker-compose --version
```

## Bước 2: Triển Khai Hệ Thống

```bash
# Chạy script deployment
./deploy.sh
```

Script này sẽ:
1. Clean up containers cũ
2. Build và start tất cả services
3. Chờ services ready
4. Tạo MinIO bucket
5. Submit Flink SQL jobs
6. Hiển thị thông tin truy cập

## Bước 3: Xác Minh Triển Khai

### Kiểm tra Services

```bash
# Kiểm tra containers đang chạy
docker ps

# Kiểm tra logs
docker-compose logs -f postgres
docker-compose logs -f jobmanager
docker-compose logs -f minioserver
```

### Truy Cập Web UIs

- **Flink Web UI**: http://localhost:8081
- **PostgreSQL (pgAdmin)**: http://localhost:5050
- **MinIO Console**: http://localhost:9001
- **Dremio**: http://localhost:9047
- **Apache Superset**: http://localhost:8088
- **Jupyter Notebook**: http://localhost:8888
- **Apache Airflow**: http://localhost:8080
- **Nessie**: http://localhost:19120

### Thông Tin Đăng Nhập

| Service | Username | Password |
|---------|----------|----------|
| PostgreSQL | admin | admin |
| pgAdmin | admin@admin.com | admin |
| MinIO | minioadmin | minioadmin |
| Superset | admin | admin |
| Jupyter | - | 123456aA@ |
| Airflow | admin | admin |

## Bước 4: Test CDC Pipeline

```bash
# Chạy test CDC
./test-cdc.sh
```

Script test sẽ:
1. Insert data mới
2. Update data hiện tại  
3. Delete data
4. Kiểm tra status Flink jobs
5. Hiển thị hướng dẫn verify kết quả

## Bước 5: Xác Minh Dữ Liệu

### 1. Kiểm tra PostgreSQL
```sql
-- Truy cập pgAdmin hoặc psql
SELECT COUNT(*) FROM public.demographics;
SELECT * FROM public.demographics LIMIT 10;
```

### 2. Kiểm tra Flink Jobs
- Vào http://localhost:8081
- Kiểm tra Running Jobs
- Xem metrics và checkpoints

### 3. Kiểm tra MinIO
- Vào http://localhost:9001
- Browser bucket `lakehouse`
- Kiểm tra folder `warehouse`

### 4. Kiểm tra Iceberg với Dremio
- Vào http://localhost:9047
- Thêm Nessie source:
  - Type: Nessie
  - Endpoint: http://nessie:19120/api/v1
  - Authentication: None
- Query bảng: `SELECT * FROM lakehouse_catalog.demographics LIMIT 10`

## Bước 6: Monitoring với Airflow

- Vào http://localhost:8080
- Enable DAG `cdc_data_lakehouse_pipeline`
- Monitor các task execution

## Troubleshooting

### 1. PostgreSQL Connection Issues
```bash
# Kiểm tra PostgreSQL logs
docker-compose logs postgres

# Test connection
docker exec -it postgres psql -U admin -d demographics
```

### 2. Flink Job Failures
```bash
# Kiểm tra Flink logs
docker-compose logs jobmanager
docker-compose logs taskmanager

# Restart Flink if needed
docker-compose restart jobmanager taskmanager
```

### 3. CDC Không Hoạt Động
```bash
# Kiểm tra replication slot
docker exec -it postgres psql -U admin -d demographics -c "SELECT * FROM pg_replication_slots;"

# Kiểm tra publication
docker exec -it postgres psql -U admin -d demographics -c "SELECT * FROM pg_publication;"
```

### 4. MinIO/S3 Issues
```bash
# Kiểm tra MinIO logs
docker-compose logs minioserver

# Test bucket access
docker exec minioserver mc ls local/lakehouse
```

## Performance Tuning

### PostgreSQL
- Tăng `max_wal_size` và `checkpoint_completion_target`
- Monitor `pg_stat_replication`

### Flink
- Tăng parallelism cho large datasets
- Tune checkpoint interval
- Adjust memory settings

### MinIO
- Use multiple drives cho production
- Enable versioning
- Configure lifecycle policies

## Production Considerations

1. **Security**: Thay đổi default passwords
2. **Backup**: Setup backup cho PostgreSQL và MinIO
3. **Monitoring**: Add Prometheus/Grafana
4. **Scaling**: Use Kubernetes cho production
5. **Network**: Use proper network security
6. **SSL/TLS**: Enable HTTPS cho all services

## Dọn Dẹp

```bash
# Stop và remove containers
docker-compose down -v

# Remove images nếu cần
docker system prune -a
```

## Tài Liệu Tham Khảo

- [Apache Flink CDC Documentation](https://ververica.github.io/flink-cdc-connectors/)
- [Apache Iceberg Documentation](https://iceberg.apache.org/)
- [Nessie Documentation](https://projectnessie.org/)
- [Dremio Documentation](https://docs.dremio.com/)

---

🎉 **Chúc mừng!** Bạn đã triển khai thành công hệ thống Data Lakehouse với CDC! 