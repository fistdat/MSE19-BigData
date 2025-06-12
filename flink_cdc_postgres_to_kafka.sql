-- Flink SQL: PostgreSQL CDC to Kafka Streaming
-- Creates real-time streaming from PostgreSQL -> Kafka

-- Create source table connected to PostgreSQL (CDC)
CREATE TABLE postgres_demographics (
  id INT,
  name STRING,
  age INT,
  city STRING,
  salary DECIMAL(10,2),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'postgres-cdc',
  'hostname' = 'postgres',
  'port' = '5432',
  'username' = 'bigdata_user',
  'password' = 'bigdata_password',
  'database-name' = 'bigdata_db',
  'schema-name' = 'public',
  'table-name' = 'demographics',
  'decoding.plugin.name' = 'pgoutput',
  'slot.name' = 'flink_slot'
);

-- Create target table for Kafka output
CREATE TABLE kafka_demographics (
  id INT,
  name STRING,
  age INT,
  city STRING,
  salary DECIMAL(10,2),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'kafka',
  'topic' = 'demographics-cdc',
  'properties.bootstrap.servers' = 'kafka:9092',
  'properties.group.id' = 'flink-cdc-group',
  'format' = 'json',
  'scan.startup.mode' = 'earliest-offset'
);

-- Start CDC streaming: PostgreSQL -> Kafka
INSERT INTO kafka_demographics
SELECT id, name, age, city, salary
FROM postgres_demographics; 