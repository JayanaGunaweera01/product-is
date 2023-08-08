#!/bin/bash

# Define color variables
GREEN='\033[0;32m\033[1m' # green color
RED='\033[0;31m\033[1m'   # red color
RESET='\033[0m'           # reset color

# Get the value of the inputs
os=$1
keyJsonFile=$2
currentVersion=$3

# Setup file and path based on OS
case $os in
  "ubuntu-latest")
    dir_path="/home/runner/work/product-is/product-is/.github/migration-tester/migration-automation/IS_HOME_OLD"
    ;;
  "macos-latest")
    dir_path="/Users/runner/work/product-is/product-is/.github/migration-tester/migration-automation/IS_HOME_OLD"
    ;;
  *) 
    echo -e "${RED}Unsupported OS type. Only 'ubuntu-latest' and 'macos-latest' are supported.${RESET}"
    exit 1
    ;;
esac

# Navigate to the directory
if cd "$dir_path"; then
  echo -e "${GREEN}==> Successfully navigated to $dir_path${RESET}"
else
  echo -e "${RED}Error navigating to $dir_path. Please check if the directory exists.${RESET}"
  exit 1
fi

# Source the env.sh file
if chmod +x env.sh && source ./env.sh; then
  echo -e "${GREEN}==> Env file for $os sourced successfully${RESET}"
else
  echo -e "${RED}Error sourcing env.sh. Please check the file permissions and contents.${RESET}"
  exit 1
fi


# Initialize file_id variable
file_id=""

# Check the value of currentVersion and assign the corresponding environment variable to file_id
case $currentVersion in
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

# Download the file using the access token
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

# Download the file using the access token
response=$(curl -s -L -o wso2is.zip "$file_url" \
  --header "Authorization: Bearer $access_token" \
  --header "Accept: application/json")

# Check if the response contains any error message
if echo "$response" | grep -q '"error":'; then
  # If there is an error, print the failure message with the error description
  error_description=$(echo "$response" | jq -r '.error_description')
  echo -e "${RED}${BOLD}Failure in downloading Identity Server "$currentVersion" $error_description${NC}"
else
  # If there is no error, print the success message
  echo -e "${PURPLE}${BOLD}Success: IS downloaded successfully.${NC}"
fi

# Unzip IS archive
unzip -qq *.zip &
wait $!
echo "${GREEN}==> Unzipped  downloaded IS zip${RESET}"

ls -a

