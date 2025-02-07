#!/bin/bash

CUSTOMER=$1
RESOURCE_GROUP="${CUSTOMER}-iotistic-node-red-group"
LOCATION="canadacentral"
PLAN="iotistic-node-red-plan"
STORAGE_ACCOUNT="iotisticnoderedstorage"
DOCKER_IMAGE="nodered/node-red:4.0"
SHARE_NAME="${CUSTOMER}-node-red-share"
VOLUME_NAME="${CUSTOMER}-node-red-volume"
APP_NAME="${CUSTOMER}-node-red-app"
DOMAIN="iotistic.ca"
HOSTNAME="${CUSTOMER}.${DOMAIN}"


# Check if the resource group exists
az group show --name $RESOURCE_GROUP &> /dev/null
if [ $? -eq 0 ]; then
    echo "Resource group '$RESOURCE_GROUP' already exists."
else
    echo "Resource group '$RESOURCE_GROUP' does not exist. Creating it..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
fi

# Check if the app service plan exists
if ! az appservice plan show --name $PLAN --resource-group $RESOURCE_GROUP &> /dev/null; then
    az appservice plan create --name $PLAN --resource-group $RESOURCE_GROUP --sku B1 --is-linux
else
    echo "App Service Plan '$PLAN' already exists."
fi

# Check if the storage account exists
az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP &> /dev/null
if [ $? -ne 0 ]; then
    echo "Storage account '$STORAGE_ACCOUNT' does not exist. Creating it..."
    az storage account create --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard_LRS
else
    echo "Storage account '$STORAGE_ACCOUNT' already exists."
fi

# Get the storage account key
STORAGE_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query [0].value -o tsv)

# Check if the storage key was retrieved successfully
if [ -z "$STORAGE_KEY" ]; then
  echo "Failed to retrieve storage account key for $STORAGE_ACCOUNT. Exiting..."
  exit 1
fi


# Create Azure File Share
az storage share create --name "${SHARE_NAME}" --account-name $STORAGE_ACCOUNT --account-key $STORAGE_KEY

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

# Add Custom Domain
# Run the command and capture both stdout and stderr
error_message=$(az webapp config hostname add --resource-group $RESOURCE_GROUP --webapp-name "${APP_NAME}" --hostname "${HOSTNAME}" 2>&1)
# Check if the command failed (if error_message contains "was not found")
if echo "$error_message" | grep -q "was not found"; then
    # Extract the verification ID from the error message
    verification_id=$(echo "$error_message" | sed -E 's/.*to ([a-f0-9]+) was not found.*/\1/')
    echo "Verification ID: $verification_id"
else
    echo "No error or domain verification required."

fi

# # Add TXT record to GoDaddy DNS ---SHIT, HAVE TO HAVE MORE THAN 20 DOMAINS TO USE GODADDY API
# api_url="https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT"
# txt_value="${verification_id}"
# json_payload="[ { \"data\": \"$txt_value\", \"name\": \"_acme-challenge.${CUSTOMER}\", \"ttl\": 600 } ]"

# response=$(curl -X PUT "$api_url" \
#     -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" \
#     -H "Content-Type: application/json" \
#     -d "$json_payload")

# echo "GoDaddy API response: $response"

# # Wait for DNS propagation
# echo "Waiting for DNS propagation (this can take up to 60 minutes)..."
# sleep 600 # Sleep for 10 minutes 

# # Check the status of the hostname/domain verification
# hostname_status=$(az webapp config hostname show --resource-group $RESOURCE_GROUP --webapp-name "${APP_NAME}" --hostname "${HOSTNAME}" 2>&1)

# # If the domain is verified, the status message will contain "hostname validation successful"
# if echo "$hostname_status" | grep -q "hostname validation successful"; then
#     echo "Domain '${HOSTNAME}' is successfully verified and linked."
# else
#     echo "Domain '${HOSTNAME}' is not verified yet. Please ensure the TXT record is correctly set in your DNS provider."
# fi
