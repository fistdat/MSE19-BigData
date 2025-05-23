# Hệ Thống Data Lakehouse - Phân Tích Dữ Liệu Dân Số Thành Phố Mỹ

## Tổng Quan Hệ Thống

Dự án này xây dựng một kiến trúc Data Lakehouse hiện đại kết hợp nhiều công nghệ Big Data để xử lý và phân tích dữ liệu nhân khẩu học của các thành phố tại Mỹ. Hệ thống được thiết kế như một nền tảng dữ liệu hoàn chỉnh sử dụng Docker Container để dễ dàng triển khai và mở rộng.

## Kiến Trúc Hệ Thống

### 1. Thành Phần Lưu Trữ Dữ Liệu

- **PostgreSQL**: Cơ sở dữ liệu quan hệ lưu trữ dữ liệu gốc
  - Lưu trữ dữ liệu nhân khẩu học từ tệp `us-cities-demographics.csv`
  - Cấu hình với người dùng: admin, mật khẩu: admin
  - Cổng: 5432

- **pgAdmin**: Công cụ quản lý PostgreSQL trực quan
  - Truy cập qua cổng: 5050
  - Đăng nhập: admin@admin.com, mật khẩu: admin

- **MinIO**: Lưu trữ đối tượng tương thích S3
  - Đóng vai trò là kho lưu trữ cho Data Lake
  - Truy cập API qua cổng: 9000
  - Truy cập Console qua cổng: 9001
  - Thông tin đăng nhập: minioadmin / minioadmin

- **Apache Iceberg**: Định dạng bảng cho Data Lake
  - Hỗ trợ giao dịch ACID
  - Tiến hóa schema
  - Du hành thời gian (time travel)

- **Nessie**: Hệ thống kiểm soát phiên bản cho bảng Iceberg
  - Chạy trên cổng: 19120

### 2. Thành Phần Xử Lý Dữ Liệu

- **Apache Flink**: Hệ thống xử lý luồng dữ liệu
  - JobManager chạy trên cổng: 8081 (Giao diện Web UI)
  - Hỗ trợ xử lý dữ liệu theo thời gian thực
  - Sử dụng để chuyển đổi dữ liệu từ PostgreSQL sang Iceberg

- **Change Data Capture (CDC)**: Bắt thay đổi dữ liệu từ PostgreSQL
  - Kết nối Flink với PostgreSQL thông qua connector postgres-cdc
  - Theo dõi thay đổi dữ liệu theo thời gian thực
  - Người dùng chuyên dụng: cdc_user

### 3. Thành Phần Điều Phối Quy Trình

- **Apache Airflow**: Quản lý và lập lịch quy trình dữ liệu
  - Webserver chạy trên cổng: 8080
  - Scheduler theo dõi và thực thi các DAG
  - Dùng LocalExecutor để xử lý các nhiệm vụ
  - Thông tin đăng nhập: admin / admin

### 4. Thành Phần Truy Vấn và Phân Tích

- **Dremio**: Công cụ truy vấn Data Lakehouse
  - Truy cập qua cổng: 9047
  - Cung cấp giao diện SQL cho việc truy vấn dữ liệu Iceberg
  - Hỗ trợ tối ưu hóa truy vấn và bộ nhớ đệm

- **Apache Superset**: Công cụ trực quan hóa dữ liệu
  - Truy cập qua cổng: 8088
  - Kết nối với Dremio để truy vấn dữ liệu Iceberg
  - Cung cấp khả năng tạo dashboard tương tác
  - Thông tin đăng nhập: admin / admin

- **Jupyter Notebook**: Môi trường phân tích dữ liệu
  - Truy cập qua cổng: 8888
  - Hỗ trợ Python và các thư viện phân tích dữ liệu
  - Mật khẩu: 123456aA@

## Luồng Dữ Liệu

1. Dữ liệu nhân khẩu học thành phố Mỹ được nạp vào PostgreSQL
2. Flink sử dụng CDC (Change Data Capture) để bắt các thay đổi dữ liệu từ PostgreSQL
3. Dữ liệu được biến đổi và ghi vào bảng Iceberg trong MinIO (S3)
4. Dremio cung cấp khả năng truy vấn SQL đến bảng Iceberg
5. Superset và Jupyter kết nối với Dremio để trực quan hóa và phân tích

## Cấu Trúc Dữ Liệu

Dữ liệu nhân khẩu học thành phố Mỹ bao gồm các trường:
- city: Tên thành phố
- state: Tên tiểu bang
- median_age: Tuổi trung bình
- male_population: Dân số nam
- female_population: Dân số nữ
- total_population: Tổng dân số
- number_of_veterans: Số cựu chiến binh
- foreign_born: Số người sinh ra ở nước ngoài
- average_household_size: Kích thước hộ gia đình trung bình
- state_code: Mã tiểu bang
- race: Chủng tộc
- count: Số lượng

## Cách Sử Dụng

1. Khởi động hệ thống:
   ```
   docker-compose up -d
   ```

2. Truy cập các công cụ:
   - pgAdmin: http://localhost:5050
   - Flink UI: http://localhost:8081
   - MinIO Console: http://localhost:9001
   - Dremio: http://localhost:9047
   - Airflow: http://localhost:8080
   - Superset: http://localhost:8088
   - Jupyter: http://localhost:8888

3. Tạo bucket trong MinIO:
   - Đăng nhập vào MinIO Console
   - Tạo bucket "lakehouse"

4. Thực thi pipeline với Flink SQL:
   - Sử dụng mã SQL trong tệp `postgres_to_iceberg.sql`

## Đặc Điểm Kỹ Thuật

- Hệ thống sử dụng CDC để bắt dữ liệu liên tục từ PostgreSQL
- Apache Iceberg cung cấp giao dịch ACID, tiến hóa schema và khả năng quay ngược thời gian
- Kiến trúc theo mô hình Data Lakehouse hiện đại, kết hợp lưu trữ Data Lake với tính năng giống cơ sở dữ liệu
- Toàn bộ môi trường được đóng gói trong Docker Compose để dễ dàng triển khai

## Các Điểm Tích Hợp

- Flink SQL được sử dụng để định nghĩa pipeline ETL từ PostgreSQL đến Iceberg
- MinIO cung cấp lưu trữ tương thích S3 cho bảng Iceberg
- Nessie quản lý phiên bản cho bảng Iceberg
- Airflow điều phối quy trình ETL
- Dremio đóng vai trò là công cụ truy vấn cho các ứng dụng phía sau

## Nguồn Dữ Liệu

- Dữ liệu nhân khẩu học thành phố Mỹ: https://www.kaggle.com/datasets/mexwell/us-cities-demographics
