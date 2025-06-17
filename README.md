# DC Data Ingestion and CI/CD Pipeline Assignment

## Architecture

### Technologies Used

This solution uses the following services or tools

- Google Cloud Storage: Where files are staged as well as where configurations for schemas or Cloud Run are stored.
- Dataflow Pipeline: Processes data that has been staged in GCS and loads it into BigQuery.
- BigQuery: Final data lake storage location for files that have been ingested.
- Cloud Run: Ingests data and performs initial preperation to have it ready for the Dataflow Pipeline.
- Terraform: IaC solution used to define the resources for running the pipeline as well as storing state.
- Cloud Build: Used to deploy the terraform resource defenitions and trigger events in the Google Cloud Platform to kick off processing.
- Github: The repository that holds the terraform configuration and Cloud Build yaml.
- Python: Any scripting for Cloud Run is done in Python.
- Eventarc Trigger: This watches the logs for specific Cloud Build events to kick off the Cloud Run service.

### Pipeline flow

When a change is made in github a new cloud build deployment can be done. If this deployment makes a change then it will actiavte the eventarc trigger and cause the Cloud Run service to run. This will execute the Python script on the container and grab the desired data a load it into GCS. Once in GCS the scheduled Dataflow Pipeline job will run and convert the csv file to big query.

## CI/CD Release Strategy

The CI/CD release strategy is a standard strategy for terraform. Since everything is defined in terraform including cloud run and dataflow a standard approach of branching a merging can be used.

When a new release is going to take place the developer would create a branch from main and begin working in the dev directory. This directory is configured to deploy to the dev project/environment via the variables.tf. A cloud trigger would watch for the new branch and when commits were made would allow for a cloud build. This would run everyhthing up to a terraform plan to allow you to see your changes. If everything looks good this would be merged and deployed by another cloud build run. The eventarc triggers would kick off for existing cloud run services that neeed to run. Once the lower environment was verified another branch would be made with changes to the prod directory with the same changes. This would allow for a cloud build job that would run a terrform plan against prod and if verified and merged these changes would trigger the cloud build job to deploy to the production environment.

## Imporvements

With more time there are a couple things I would like to improve for this design

- I would like to take advantage of terraforms modules to make the process for releasing new/additional cloud run jobs easier and reduce a lot of the redundancy and length of the current main.tf.
- There is no monitoring or alerting for any of this configured. I would like to add alerts for successes and failures as well as add metrics to get incite into processing times for cloud run and dataflow.