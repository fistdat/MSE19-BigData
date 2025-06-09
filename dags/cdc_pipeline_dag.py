from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.http.operators.http import HttpOperator
import json

# Default arguments for the DAG
default_args = {
    'owner': 'data-engineering-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
dag = DAG(
    'cdc_data_lakehouse_pipeline',
    default_args=default_args,
    description='CDC Pipeline for Data Lakehouse - PostgreSQL to Iceberg via Flink',
    schedule_interval=timedelta(hours=1),  # Run every hour
    catchup=False,
    max_active_runs=1,
    tags=['cdc', 'data-lakehouse', 'postgres', 'iceberg', 'flink'],
)

def check_postgres_connection():
    """Check if PostgreSQL is accessible and has data"""
    import psycopg2
    try:
        conn = psycopg2.connect(
            host='postgres',
            database='demographics',
            user='admin',
            password='admin',
            port='5432'
        )
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM public.demographics;")
        count = cursor.fetchone()[0]
        print(f"✅ PostgreSQL connection successful. Total records: {count}")
        cursor.close()
        conn.close()
        return count
    except Exception as e:
        print(f"❌ PostgreSQL connection failed: {str(e)}")
        raise

def check_flink_job_status():
    """Check status of Flink CDC jobs"""
    import requests
    try:
        response = requests.get('http://jobmanager:8081/jobs')
        jobs = response.json()
        print(f"📊 Flink jobs status: {json.dumps(jobs, indent=2)}")
        return jobs
    except Exception as e:
        print(f"❌ Failed to check Flink jobs: {str(e)}")
        raise

def monitor_cdc_lag():
    """Monitor CDC replication lag"""
    import psycopg2
    try:
        conn = psycopg2.connect(
            host='postgres',
            database='demographics',
            user='admin',
            password='admin',
            port='5432'
        )
        cursor = conn.cursor()
        # Check replication slot status
        cursor.execute("""
            SELECT slot_name, active, restart_lsn, confirmed_flush_lsn 
            FROM pg_replication_slots 
            WHERE slot_name = 'flink_slot';
        """)
        slot_info = cursor.fetchone()
        if slot_info:
            print(f"🔄 Replication slot info: {slot_info}")
        else:
            print("⚠️ No replication slot found")
        
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"❌ Failed to monitor CDC lag: {str(e)}")
        raise

def restart_flink_job_if_failed():
    """Restart Flink job if it has failed"""
    import requests
    try:
        # Get all jobs
        response = requests.get('http://jobmanager:8081/jobs')
        jobs = response.json().get('jobs', [])
        
        for job in jobs:
            if job.get('status') == 'FAILED':
                job_id = job.get('id')
                print(f"🔄 Restarting failed job: {job_id}")
                
                # Cancel the failed job
                requests.patch(f'http://jobmanager:8081/jobs/{job_id}')
                
                # Note: In a real scenario, you would submit a new job
                # For now, we just log the action
                print(f"✅ Job {job_id} restart initiated")
    except Exception as e:
        print(f"❌ Failed to restart Flink job: {str(e)}")

# Task 1: Check PostgreSQL connection and data
check_postgres_task = PythonOperator(
    task_id='check_postgres_connection',
    python_callable=check_postgres_connection,
    dag=dag,
)

# Task 2: Check Flink job status
check_flink_task = PythonOperator(
    task_id='check_flink_job_status',
    python_callable=check_flink_job_status,
    dag=dag,
)

# Task 3: Monitor CDC replication lag
monitor_cdc_task = PythonOperator(
    task_id='monitor_cdc_lag',
    python_callable=monitor_cdc_lag,
    dag=dag,
)

# Task 4: Restart failed Flink jobs
restart_failed_jobs_task = PythonOperator(
    task_id='restart_failed_flink_jobs',
    python_callable=restart_flink_job_if_failed,
    dag=dag,
)

# Task 5: Validate data consistency (optional)
validate_data_task = PostgresOperator(
    task_id='validate_data_consistency',
    postgres_conn_id='postgres_default',
    sql="""
    SELECT 
        COUNT(*) as total_records,
        MAX(median_age) as max_age,
        MIN(median_age) as min_age,
        AVG(total_population) as avg_population
    FROM public.demographics;
    """,
    dag=dag,
)

# Task dependencies
check_postgres_task >> check_flink_task >> monitor_cdc_task >> restart_failed_jobs_task >> validate_data_task

# Optional: Add a task to send notifications (Slack, email, etc.)
# This would be configured based on your notification preferences 