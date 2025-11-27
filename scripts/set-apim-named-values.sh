#!/bin/bash

# Generates and sets cryptographically secure encryption key and IV for APIM Named Values.
#
# This script generates a 256-bit AES encryption key and 128-bit initialization vector (IV),
# then stores them as named values in Azure API Management service for use in OAuth operations.
#
# Usage: ./set-apim-named-values.sh

set -e

# Get values from azd environment
echo "Retrieving values from azd environment..."
eval "$(azd env get-values)"

# Validate required environment variables
if [[ -z "$AZURE_APIM_NAME" ]]; then
    echo "Error: AZURE_APIM_NAME in azd environment must be set" >&2
    exit 1
fi

if [[ -z "$AZURE_RESOURCE_GROUP" ]]; then
    echo "Error: AZURE_RESOURCE_GROUP in azd environment must be set" >&2
    exit 1
fi

if [[ -z "$AZURE_FUNCTION_NAME" ]]; then
    echo "Error: AZURE_FUNCTION_NAME in azd environment must be set" >&2
    exit 1
fi

echo "Generating secure named values for APIM: $AZURE_APIM_NAME in resource group: $AZURE_RESOURCE_GROUP, post deployment"

# Part 1: Generate cryptographic values
# Due to SFI policy restrictions, we cannot use DeploymentScripts to run this script during deployment
# so we run it as a post deployment step in azd

# Generate random 32 bytes (256-bit) key for AES-256
echo "Generating 256-bit encryption key..."
keyBase64=$(openssl rand -base64 32)
echo "Generated 256-bit encryption key"

# Generate random 16 bytes (128-bit) IV
echo "Generating 128-bit initialization vector..."
ivBase64=$(openssl rand -base64 16)
echo "Generated 128-bit initialization vector"

# Set the EncryptionKey named value
echo "Setting EncryptionKey named value..."
az apim nv create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --service-name "$AZURE_APIM_NAME" \
    --named-value-id "EncryptionKey" \
    --display-name "EncryptionKey" \
    --value "$keyBase64" \
    --secret true \
    || { echo "Error: Failed to create EncryptionKey named value" >&2; exit 1; }
echo "Successfully created EncryptionKey named value"

# Set the EncryptionIV named value
echo "Setting EncryptionIV named value..."
az apim nv create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --service-name "$AZURE_APIM_NAME" \
    --named-value-id "EncryptionIV" \
    --display-name "EncryptionIV" \
    --value "$ivBase64" \
    --secret true \
    || { echo "Error: Failed to create EncryptionIV named value" >&2; exit 1; }
echo "Successfully created EncryptionIV named value"

# Part 2: Get and set the mcp_extension system key
# Azure Functions mcp_extension system key is only available after the source code is deployed,
# so we are forced to set the mcp-extension-key as a post deployment step in azd

# Get the mcp_extension system key from the Function App
echo "Retrieving mcp_extension system key from Function App..."
mcpExtensionKey=$(az functionapp keys list \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_FUNCTION_NAME" \
    --query systemKeys.mcp_extension \
    --output tsv 2>/dev/null || echo "")

if [[ -z "$mcpExtensionKey" ]]; then
    echo "Warning: Failed to retrieve mcp_extension system key" >&2
else
    echo "Successfully retrieved mcp_extension system key"
fi

# Set the mcp-extension-key named value
echo "Setting mcp-extension-key named value..."
az apim nv create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --service-name "$AZURE_APIM_NAME" \
    --named-value-id "mcp-extension-key" \
    --display-name "mcp-extension-key" \
    --value "$mcpExtensionKey" \
    --secret true \
    || { echo "Error: Failed to create mcp-extension-key named value" >&2; exit 1; }
echo "Successfully created mcp-extension-key named value"

echo "Successfully configured named values in APIM"
