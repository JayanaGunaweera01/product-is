#!/bin/bash

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
echo $access_token

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
