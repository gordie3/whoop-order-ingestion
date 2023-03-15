#!/bin/bash

echo "Executing create_pkg.sh..."

cd $path_cwd
dir_name=lambda_dist_pkg/
mkdir $dir_name

# Create and activate virtual environment...
virtualenv env_whoop_order_ingestion
source $path_cwd/env_whoop_order_ingestion/bin/activate

# Installing python dependencies...
FILE=$path_cwd/src/requirements.txt

if [ -f "$FILE" ]; then
  echo "Installing dependencies..."
  echo "From: requirement.txt file exists..."
  pip install -r "$FILE"

else
  echo "Error: requirement.txt does not exist!"
fi

# Deactivate virtual environment...
deactivate

# Create deployment package...
echo "Creating deployment package..."
cd env_whoop_order_ingestion/lib/python3.9/site-packages/
cp -r . $path_cwd/$dir_name
cp -r $path_cwd/src/. $path_cwd/$dir_name

# Removing virtual environment folder...
echo "Removing virtual environment folder..."
rm -rf $path_cwd/env_whoop_order_ingestion

echo "Finished script execution!"
