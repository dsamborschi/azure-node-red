#!/bin/bash

# Global
STORAGE_ACCOUNT="iotisticnoderedstorage"
ROOT_RESOURCE_GROUP="node-red-group"
DOMAIN="iotistic.ca"
HOSTNAME="${CUSTOMER}.${DOMAIN}"
LOCATION="canadacentral"

# Customer specific
CUSTOMER=$1
RESOURCE_GROUP="${CUSTOMER}-node-red-group"
PLAN="${CUSTOMER}-node-red-plan"
DOCKER_IMAGE="dsamborschi42/iotistic-node-red:latest"
SHARE_NAME="${CUSTOMER}-node-red-share"
VOLUME_NAME="${CUSTOMER}-node-red-volume"
APP_NAME="${CUSTOMER}-node-red-app"



# Check if the resource group exists
az group show --name $RESOURCE_GROUP &> /dev/null
if [ $? -eq 0 ]; then
    echo "Resource group '$RESOURCE_GROUP' already exists."
else
    echo "Resource group '$RESOURCE_GROUP' does not exist. Creating it..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
fi

# Check if the storage account exists
az storage account show --name $STORAGE_ACCOUNT --resource-group $ROOT_RESOURCE_GROUP &> /dev/null
if [ $? -ne 0 ]; then
    echo "Storage account '$STORAGE_ACCOUNT' does not exist. Creating it..."
    az storage account create --name $STORAGE_ACCOUNT --resource-group $ROOT_RESOURCE_GROUP --location $LOCATION --sku Standard_LRS
else
    echo "Storage account '$STORAGE_ACCOUNT' already exists."
fi

# Get the storage account key
STORAGE_KEY=$(az storage account keys list --resource-group $ROOT_RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query [0].value -o tsv)

# Check if the storage key was retrieved successfully
if [ -z "$STORAGE_KEY" ]; then
  echo "Failed to retrieve storage account key for $STORAGE_ACCOUNT. Exiting..."
  exit 1
fi


# Create Azure File Share
az storage share create --name "${SHARE_NAME}" --account-name $STORAGE_ACCOUNT --account-key $STORAGE_KEY

# Check if the app service plan exists
if ! az appservice plan show --name $PLAN --resource-group $RESOURCE_GROUP &> /dev/null; then
    az appservice plan create --name $PLAN --resource-group $RESOURCE_GROUP --sku B1 --is-linux
else
    echo "App Service Plan '$PLAN' already exists."
fi

# Deploy Web App
az webapp create --resource-group $RESOURCE_GROUP --plan $PLAN --name "${APP_NAME}" --deployment-container-image-name $DOCKER_IMAGE

# Attach Volume
az webapp config storage-account add \
  --resource-group $RESOURCE_GROUP \
  --name "${APP_NAME}" \
  --custom-id "${VOLUME_NAME}" \
  --storage-type AzureFiles \
  --account-name $STORAGE_ACCOUNT \
  --share-name "${SHARE_NAME}" \
  --access-key $STORAGE_KEY \
  --mount-path "/data"

# Add Custom Domain and run the command and capture both stdout and stderr
error_message=$(az webapp config hostname add --resource-group $RESOURCE_GROUP --webapp-name "${APP_NAME}" --hostname "${HOSTNAME}" 2>&1)
# Check if the command failed (if error_message contains "was not found")
if echo "$error_message" | grep -q "was not found"; then
    # Extract the verification ID from the error message
    verification_id=$(echo "$error_message" | sed -E 's/.*to ([a-f0-9]+) was not found.*/\1/')
    echo "Verification ID: $verification_id"
else
    echo "No error or domain verification required."

fi

