"""
Load Testing DAG for Apache Airflow 3.0.0
This DAG simulates heavy workload for testing purposes
"""

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from datetime import datetime, timedelta
import time
import random

# Default arguments
default_args = {
    'owner': 'airflow',
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'start_date': datetime(2024, 1, 1),
}

# Define the DAG
with DAG(
    'load_testing_dag',
    default_args=default_args,
    description='Load testing DAG with heavy compute tasks',
    schedule='@hourly',
    catchup=False,
    tags=['testing', 'load-test'],
) as dag:
    
    def cpu_intensive_task(task_id, duration_seconds=10):
        """Simulate CPU-intensive workload"""
        print(f'[{task_id}] Starting CPU-intensive computation for {duration_seconds}s')
        start_time = time.time()
        
        # CPU-intensive computation
        result = 0
        for i in range(100000000):
            result += i ** 2
        
        elapsed = time.time() - start_time
        print(f'[{task_id}] Completed in {elapsed:.2f}s (result: {result})')
        return elapsed
    
    def memory_task(task_num=1, size_mb=100):
        """Simulate memory-intensive workload"""
        print(f'[memory_task_{task_num}] Allocating {size_mb}MB of memory')
        # Allocate memory
        large_list = [random.random() for _ in range(size_mb * 10000)]
        print(f'[memory_task_{task_num}] Memory allocation complete: {len(large_list)} items')
        return len(large_list)
    
    def io_task(task_num=1, iterations=1000):
        """Simulate I/O operations"""
        print(f'[io_task_{task_num}] Starting {iterations} I/O operations')
        for i in range(iterations):
            # Simulate I/O with a small sleep
            time.sleep(0.001)
            if (i + 1) % 100 == 0:
                print(f'[io_task_{task_num}] Completed {i + 1}/{iterations} operations')
        print(f'[io_task_{task_num}] All I/O operations completed')
        return iterations
    
    def data_processing_task(num_records=10000):
        """Simulate data processing workload"""
        print(f'[data_processing_task] Processing {num_records} records')
        
        processed = 0
        for record_id in range(num_records):
            # Simulate record processing
            value = sum([i ** 2 for i in range(100)])
            processed += 1
            
            if (record_id + 1) % 1000 == 0:
                print(f'[data_processing_task] Processed {processed}/{num_records} records')
        
        print(f'[data_processing_task] Data processing complete')
        return processed
    
    # Create parallel CPU-intensive tasks
    cpu_task_1 = PythonOperator(
        task_id='cpu_intensive_1',
        python_callable=cpu_intensive_task,
        op_kwargs={'task_id': 'cpu_1', 'duration_seconds': 10},
    )
    
    cpu_task_2 = PythonOperator(
        task_id='cpu_intensive_2',
        python_callable=cpu_intensive_task,
        op_kwargs={'task_id': 'cpu_2', 'duration_seconds': 10},
    )
    
    # Create memory tasks
    memory_task_1 = PythonOperator(
        task_id='memory_task_1',
        python_callable=memory_task,
        op_kwargs={'task_num': 1, 'size_mb': 50},
    )
    
    memory_task_2 = PythonOperator(
        task_id='memory_task_2',
        python_callable=memory_task,
        op_kwargs={'task_num': 2, 'size_mb': 50},
    )
    
    # Create I/O tasks
    io_task_1 = PythonOperator(
        task_id='io_task_1',
        python_callable=io_task,
        op_kwargs={'task_num': 1, 'iterations': 500},
    )
    
    io_task_2 = PythonOperator(
        task_id='io_task_2',
        python_callable=io_task,
        op_kwargs={'task_num': 2, 'iterations': 500},
    )
    
    # Create data processing task
    data_processing = PythonOperator(
        task_id='data_processing',
        python_callable=data_processing_task,
        op_kwargs={'num_records': 5000},
    )
    
    # Set task dependencies for load testing pipeline
    # CPU tasks run in parallel first
    for cpu_task in [cpu_task_1, cpu_task_2]:
        for mem_task in [memory_task_1, memory_task_2]:
            cpu_task >> mem_task

    for mem_task in [memory_task_1, memory_task_2]:
        for io_task in [io_task_1, io_task_2]:
            mem_task >> io_task

    for io_task in [io_task_1, io_task_2]:
        io_task >> data_processing
