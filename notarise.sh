#!/usr/bin/env bash
# Notarise the QuickSS app

# Pre-requisites:
# 
# 1. Create an App specific password for your Apple ID
# 2. Store to 1Password as "Apple App Notarisation" with fields:
#    - username: Your Apple ID email address
#    - password: The app specific password you created
#    - team_id: Your Apple Developer Team ID
# 3. Ensure that you have an Apple "Developer ID Application" certificate in
#    the Apple Developer portal if not, create one
# 4. Download and install the Developer ID Application certificate into the keychain
# 5 Ensure that the Xcode command line tools are installed and selected
#   Use `sudo xcode-select --switch /Applications/Xcode.app` if necessary


set -euo pipefail

# If the Apple ID credentials are not set in environment variables, get them from 1Password
if [ -z "${TEAM_ID:-}" ] || [ -z "${APPLE_ID:-}" ] || [ -z "${APP_SPECIFIC_PASSWORD:-}" ]; then
    # Get the creds from 1Password
    if ! command -v op &> /dev/null; then
        echo "1Password CLI (op) is not installed. Please install it to run this script."
        exit 1
    fi

    # Sign into 1Password
    op signin

    # Get data from 1Password and extract the fields into variables, splitting on commas
    FIELDS=$(op item get "Apple App Notarisation" --fields username,password,team_id --reveal)
    IFS=',' read -r APPLE_ID APP_SPECIFIC_PASSWORD TEAM_ID <<< "$FIELDS"
fi

echo "Using Apple ID: $APPLE_ID and Team ID: $TEAM_ID"

# Extract the code signing certificate identity name. We want the one with "Developer ID Application" in its name
if [ -z "${IDENTITY:-}" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -m 1 -oE '"[^"]+"' | tr -d '"')
    if [ -z "$IDENTITY" ]; then
        echo "No valid code signing identity found."
        echo "Found:"
        security find-identity -v -p codesigning
        exit 1
    fi
fi
echo "Using identity: $IDENTITY"

# Compile QuickSS
echo "Compiling QuickSS..."
swiftc quickss.swift -o quickss


# Sign the QuickSS binary
echo "Signing QuickSS..."
codesign --timestamp --options runtime --sign "$IDENTITY" quickss
codesign --verify --verbose=4 quickss


# Submit for notarisation
echo "Submitting notarisation request for quickss.zip..."
zip -q quickss.zip quickss

submission=$(xcrun notarytool submit  --wait --no-progress -f json \
        --team-id "$TEAM_ID" \
        --apple-id "$APPLE_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        quickss.zip)

rm quickss.zip
submissionId=$(echo "$submission" | jq -r .id)

if [[ -z "$submissionId" ]]; then
    echo "Failed to submit notarisation request"
    echo "Response: $submission"
    exit 1
fi
echo "Submission ID: $submissionId"

# Read the notarisation log to determine if it worked
submissionLog=$(xcrun notarytool log \
        --apple-id "$APPLE_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --team-id "$TEAM_ID" \
        "$submissionId")

status=$(echo "$submissionLog" | jq -r '.status')
statusSummary=$(echo "$submissionLog" | jq -r '.statusSummary')
if [[ "$status" != "Accepted" ]]; then
    echo "Notarisation failed with status: $status"
    echo "Log: $submissionLog"
    exit 1
fi

echo "Notarisation completed. $statusSummary"
exit 0
