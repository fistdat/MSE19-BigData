-- Final Syntax Test for Flink SQL Client
-- Using quoted syntax for SET commands

-- Configure checkpointing with quoted syntax
SET 'execution.checkpointing.interval' = '30sec';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.backend' = 'rocksdb';
SET 'state.checkpoints.dir' = 's3a://warehouse/checkpoints';

-- Test simple table creation
CREATE TABLE test_datagen (
    id INT,
    name STRING,
    proc_time AS PROCTIME()
) WITH (
    'connector' = 'datagen',
    'rows-per-second' = '1'
);

-- Test simple query
SELECT * FROM test_datagen LIMIT 5; 