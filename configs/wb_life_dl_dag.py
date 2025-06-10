# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Example Airflow DAG that creates a Cloud Dataflow workflow which takes a
text file and adds the rows to a BigQuery table.

This DAG relies on four Airflow variables
https://airflow.apache.org/docs/apache-airflow/stable/concepts/variables.html
* project_id - Google Cloud Project ID to use for the Cloud Dataflow cluster.
* gce_zone - Google Compute Engine zone where Cloud Dataflow cluster should be
  created.
For more info on zones where Dataflow is available see:
https://cloud.google.com/dataflow/docs/resources/locations
* bucket_path - Google Cloud Storage bucket where you've stored the User Defined
Function (.js), the input file (.txt), and the JSON schema (.json).
"""

import urllib.request
import datetime

from airflow import models
from airflow.decorators import task
from airflow.utils.dates import days_ago

default_args = {
    # Tell airflow to start one day ago, so that it runs as soon as you upload it
    "start_date": days_ago(1),
    "dataflow_default_options": {
        "project": "ninth-sol-462415-k7",
        # Set to your zone
        "zone": "us-central1-a",
        # This is a subfolder for storing temporary files, like the staged pipeline job.
        "uri": "https://api.worldbank.org/v2/en/indicator/SP.DYN.LE00.IN?downloadformat=csv",
        "target_path": "gs://wb-le-task-files",
        "serviceAccountEmail": "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com",
    },
}

# Define a DAG (directed acyclic graph) of tasks.
# Any task you create within the context manager is automatically added to the
# DAG object.
with models.DAG(
    # The id you will see in the DAG airflow page
    "wb_life_dl_dag",
    default_args=default_args,
    # The interval with which to schedule the DAG
    schedule_interval=datetime.timedelta(days=1),  # Override to match your needs
) as dag:

    @task
    def download_file(uri, target_path):
        with urllib.request.urlopen(uri) as file:
            with open(target_path, "wt") as new_file:
                new_file.write(file.read())