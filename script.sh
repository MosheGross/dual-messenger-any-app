#!/bin/bash

# Step 1: Check if ADB is installed
echo "Checking if ADB is installed..."
if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: ADB is not installed or not in PATH. Please install ADB and try again."
    read -p "Press Enter to exit..."
    exit 1
fi
echo "ADB is installed."

# Step 2: Check if a device is connected
echo "Checking if a device is connected..."
DEVICE_FOUND=false

while read -r line; do
    if [[ "$line" =~ ^[0-9a-zA-Z]+[[:space:]]+device$ ]]; then
        DEVICE_FOUND=true
    fi
done < <(adb devices | tail -n +2)

if [ "$DEVICE_FOUND" = false ]; then
    echo "ERROR: No device connected. Please connect a device and try again."
    read -p "Press Enter to exit..."
    exit 1
fi
echo "A device is connected."

# Step 3: Get the DUAL_APP User ID
echo "Retrieving user list..."
DUAL_APP_ID=""

while read -r line; do
    if echo "$line" | grep -q "DUAL_APP"; then
        DUAL_APP_ID=$(echo "$line" | grep -o "{[0-9]*:" | tr -d "{" | tr -d ":")
    fi
done < <(adb shell pm list users)

if [ -z "$DUAL_APP_ID" ]; then
    echo "ERROR: DUAL_APP User not found."
    read -p "Press Enter to exit..."
    exit 1
fi
echo "DUAL_APP User found with ID: $DUAL_APP_ID"

# Step 4: Prompt for Package Name
read -p "Enter the package name to clone: " PACKAGE_NAME

if [ -z "$PACKAGE_NAME" ]; then
    echo "ERROR: No package name provided."
    read -p "Press Enter to exit..."
    exit 1
fi

# Step 5: Check if the app exists
echo "Checking if the app $PACKAGE_NAME exists on the device..."
APP_PATHS=$(adb shell pm path "$PACKAGE_NAME")

if [ -z "$APP_PATHS" ]; then
    echo "ERROR: The package \"$PACKAGE_NAME\" does not exist on the device."
    read -p "Press Enter to exit..."
    exit 1
fi
echo "The package \"$PACKAGE_NAME\" exists. Preparing to pull APK files..."

# Step 6: Create a folder for the package
mkdir -p "$PACKAGE_NAME"
cd "$PACKAGE_NAME" || exit 1

# Step 7: Pull all APK files
echo "Pulling APK files..."
while read -r apk_path; do
    apk_path=${apk_path#package:}
    adb pull "$apk_path"
done <<< "$APP_PATHS"

# Step 8: Install
filelist=()
for apk in *.apk; do
    if [ -f "$apk" ]; then
        filelist+=("$apk")
    fi
done

if [ ${#filelist[@]} -eq 0 ]; then
    echo "ERROR: No APK files found to install."
    cd ..
    rm -rf "$PACKAGE_NAME"
    read -p "Press Enter to exit..."
    exit 1
fi

echo "Installing $PACKAGE_NAME for user $DUAL_APP_ID"
adb install-multiple --user "$DUAL_APP_ID" "${filelist[@]}"

# Step 9: Copy Permissions
echo "Cloning permissions for $PACKAGE_NAME..."
while read -r line; do
    # Skip empty or invalid lines
    [ -z "$line" ] && continue
    # Extract permission and status, excluding lines with "Uid"
    if echo "$line" | grep -q "Uid"; then
        continue
    fi
    PERMISSION=$(echo "$line" | grep -o "^[a-zA-Z0-9._-]\+" | head -n 1)
    STATUS=$(echo "$line" | grep -o "[a-z]\+$" | head -n 1)
    if [ -n "$PERMISSION" ] && [ -n "$STATUS" ] && [[ "$STATUS" =~ ^(allow|deny|ignore)$ ]]; then
        adb shell appops set --user "$DUAL_APP_ID" "$PACKAGE_NAME" "$PERMISSION" "$STATUS" 2>/dev/null || echo "Warning: Failed to set permission $PERMISSION"
    fi
done < <(adb shell appops get "$PACKAGE_NAME" 2>/dev/null)

echo "$PACKAGE_NAME installed for USER $DUAL_APP_ID."

# Step 10: Clean up & Finish
cd ..
rm -rf "$PACKAGE_NAME"
echo "Press Enter to exit..."
read -r