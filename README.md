# whoop-order-ingestion

This repository contains source code for a WHOOP order ingestion Webhook API that can automatically add the data to Notion.

For more information please see the [Sync WHOOP Data With Notion](https://medium.com/@gordiewhite/sync-whoop-data-with-notion-2ec89f5c89b5) medium story

This code uses Python3.9 and Terraform Cloud.

## How To Use

In order for the Terraform code to work, you must have some variables set. Please check out `variables.tf` for more information.

Once all these variables are set and you have the `TF_CLOUD_ORGANIZATION` Environment variable set, you can run:

```
# Initialize terraform workspace
terraform init

# Bundle python lambda source code
bash scripts/create_pkg.sh

# Deploy Infrastructure
terraform apply
```
