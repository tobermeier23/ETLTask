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

import datetime

from airflow import models
from airflow.providers.google.cloud.operators.dataflow import DataflowTemplatedJobStartOperator
from airflow.utils.dates import days_ago

bucket_path = models.Variable.get("bucket_path")
project_id = models.Variable.get("project_id")
gce_zone = models.Variable.get("gce_zone")
location = models.Variable.get("location")


default_args = {
    # Tell airflow to start one day ago, so that it runs as soon as you upload it
    "start_date": days_ago(1),
    "dataflow_default_options": {
        "project": "ninth-sol-462415-k7",
        # Set to your zone
        "zone": "us-central1-a",
        # This is a subfolder for storing temporary files, like the staged pipeline job.
        "tempLocation": "gs://etl-task-files/tmp/",
        "serviceAccountEmail": "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com",
    },
}

# Define a DAG (directed acyclic graph) of tasks.
# Any task you create within the context manager is automatically added to the
# DAG object.
with models.DAG(
    # The id you will see in the DAG airflow page
    "etl_task_dataflow_dag",
    default_args=default_args,
    # The interval with which to schedule the DAG
    schedule_interval=datetime.timedelta(days=1),  # Override to match your needs
) as dag:

    start_template_job = DataflowTemplatedJobStartOperator(
        # The task id of your job
        task_id="dataflow_operator_transform_csv_to_bq",
        # The name of the template that you're using.
        # Below is a list of all the templates you can use.
        # For versions in non-production environments, use the subfolder 'latest'
        # https://cloud.google.com/dataflow/docs/guides/templates/provided-batch#gcstexttobigquery
        template="gs://dataflow-templates-us-central1/latest/GCS_CSV_to_BigQuery",
        # Use the link above to specify the correct parameters for your template.
        location="us-central1",
        parameters={
            #"javascriptTextTransformFunctionName": "etltasktransformCSVtoJSON",
            "schemaJSONPath": "gs://etl-task-files/ETLTaskjsonSchema.json",
            #"javascriptTextTransformGcsPath": "gs://etl-task-files/etltasktransformCSVtoJSON.js",
            "inputFilePattern": "gs://etl-task-files/ETLTaskinputFile.csv",
            "outputTable": "ninth-sol-462415-k7:icsa.icsa",
            "bigQueryLoadingTemporaryDirectory": "gs://etl-task-files/tmp/",
            "badRecordsOutputTable": "ninth-sol-462415-k7:icsa.bad_icsa",
            "delimiter": ",",
            "containsHeaders": "true",
            "csvFormat": "Default",
        },
    )