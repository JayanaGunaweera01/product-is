#!/bin/bash

# Define color variables
GREEN='\033[0;32m\033[1m' # green color
RED='\033[0;31m\033[1m'   # red color
NC='\033[0m'           # reset color

# Get the value of the inputs
os=$2
downloadingISVersion=$3

# Setup file and path based on OS
if [ "$os" = "ubuntu-latest" ]; then
  cd "/home/runner/work/product-is/product-is/.github/migration-tester/migration-automation"
  chmod +x env.sh
  . ./env.sh
  echo "${GREEN}==> Env file for Ubuntu sourced successfully${RESET}"

elif [ "$os" = "macos-latest" ]; then
  cd "/Users/runner/work/product-is/product-is/.github/migration-tester/migration-automation"
  chmod +x env.sh
  source ./env.sh
  echo "${GREEN}==> Env file for Mac sourced successfully${RESET}"
fi

# Initialize file_id variable
file_id=""

# Check the value of IS version and assign the corresponding environment variable to file_id
case $downloadingISVersion in
  5.9.0)
    file_id="$FILE_ID_5_9"
    ;;
  5.10.0)
    file_id="$FILE_ID_5_10"
    ;;
  5.11.0)
    file_id="$FILE_ID_5_11"
    ;;
  6.0.0)
    file_id="$FILE_ID_6_0"
    ;;
  6.1.0)
    file_id="$FILE_ID_6_1"
    ;;
  *)
    echo "No action taken.Please assign a value in env.sh if you haven't assigned a value for file ID."
    ;;
esac

# Use the file_id variable in downloading the IS zip
echo "file_id: $file_id"

# Specify the Google Drive file URL
file_url="https://www.googleapis.com/drive/v3/files/"$file_id"?alt=media"

set -euo pipefail

base64var() {
    printf "$1" | base64stream
}

base64stream() {
    base64 | tr '/+' '_-' | tr -d '=\n'
}

keyJsonFile=$1
scope="https://www.googleapis.com/auth/drive.readonly"
valid_for_sec="${3:-3600}"
valid_for_sec_numeric=$(echo "$valid_for_sec" | tr -d -c '[:digit:]')
private_key=$(jq -r .private_key "$keyJsonFile")
sa_email=$(jq -r .client_email "$keyJsonFile") || { echo "Error extracting client_email from the JSON file."; exit 1; }

header='{"alg":"RS256","typ":"JWT"}'
# Calculate the expiration time as 'valid_for_sec' seconds from now
exp=$(($(date +%s) + 60))  # Set the token to expire in 60 seconds
# The issued at time should be the current time
iat=$(date +%s)
claim=$(cat <<EOF | jq -c
  {
    "iss": "$sa_email",
    "scope": "$scope",
    "aud": "https://www.googleapis.com/oauth2/v4/token",
    "exp": $exp,
    "iat": $iat
  }
EOF
)

request_body="$(base64var "$header").$(base64var "$claim")"
signature=$(echo -n "$request_body" | openssl dgst -sha256 -sign <(echo "$private_key") -binary | base64stream)

echo "$request_body.$signature"

jwt_token=$(printf "%s.%s" "$request_body" "$signature")

# Manually construct the POST data for token request
data="grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt_token"

# Make the token request to get the access token
token_response=$(curl -s -X POST -d "$data" "https://www.googleapis.com/oauth2/v4/token")

# Extract the access token from the response
access_token=$(echo "$token_response" | jq -r .access_token)
echo " test: $access_token"

# https://drive.google.com/file/d/15nZ0gwIo-4YMibykGD979BG_olw5ChgV/view?usp=sharing

# Specify the Google Drive file URL
file_url="https://www.googleapis.com/drive/v3/files/15nZ0gwIo-4YMibykGD979BG_olw5ChgV?alt=media"

# Download the file using the access token
response=$(curl -s -L -o wso2is.zip "$file_url" \
  --header "Authorization: Bearer $access_token" \
  --header "Accept: application/json")

# Check if the response contains any error message
if echo "$response" | grep -q '"error":'; then
  # If there is an error, print the failure message with the error description
  error_description=$(echo "$response" | jq -r '.error_description')
  echo -e "Failure in downloading Identity Server $error_description"
else
  # If there is no error, print the success message
  echo "Success: IS Pack downloaded successfully."
fi

# Unzip IS archive
unzip -qq wso2is.zip

ls -a
