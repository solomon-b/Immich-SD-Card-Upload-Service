#!/usr/bin/env bash

# ============================
# Function Declarations
# ============================

# Function to read and validate configuration variables
read_config_var() {
    local env_var="$1"
    local var_name="$2"
    local description="$3"

    if [ -z "${!env_var}" ]; then
        echo "Error: $env_var environment variable is not set. Please set it to specify the path to the $description file."
        exit 1
    fi

    if [ -f "${!env_var}" ]; then
        # Read the content of the file into the variable, handling spaces and special characters
        # Using command substitution with quotes to preserve spaces
        # shellcheck disable=SC2002
        eval "$var_name=\"$(<"${!env_var}")\""
    else
        echo "Error: $description file not found at ${!env_var}"
        exit 1
    fi
}

# Function to copy image files, delete them, and remove empty folders
copy_and_delete_images() {
    local SERIAL="$1"
    local MOUNTPOINT="$2"
    local DEST_FOLDER="$TEMP_FOLDER/$SERIAL"
    echo "Copying image files from $MOUNTPOINT to $DEST_FOLDER..."

    # Create a subfolder for this serial
    mkdir -p "$DEST_FOLDER"

    # Build the include patterns for rsync
    INCLUDE_PATTERNS=()
    for EXT in "${IMAGE_EXTENSIONS[@]}"; do
        # Include both lowercase and uppercase extensions
        INCLUDE_PATTERNS+=(--include="*/")
        INCLUDE_PATTERNS+=(--include="*.${EXT}")
        INCLUDE_PATTERNS+=(--include="*.${EXT^^}")
    done
    # Exclude everything else
    EXCLUDE_PATTERN=(--exclude="*")

    # Run rsync with --remove-source-files to delete source files after copying
    rsync -av --remove-source-files "${INCLUDE_PATTERNS[@]}" "${EXCLUDE_PATTERN[@]}" "$MOUNTPOINT/" "$DEST_FOLDER/"

    echo "Deleting .thm files matching the copied images from $MOUNTPOINT..."

    # Delete .thm files only if no corresponding image files exist
    find "$MOUNTPOINT" -type f \( -iname "*.thm" \) | while read -r THM_FILE; do
        BASE_DIR="$(dirname "$THM_FILE")"
        BASE_NAME="$(basename "$THM_FILE" .thm)"

        IMAGE_FOUND=false
        for EXT in "${IMAGE_EXTENSIONS[@]}"; do
            # Check for both lowercase and uppercase extensions
            if [ -f "$BASE_DIR/$BASE_NAME.$EXT" ] || [ -f "$BASE_DIR/$BASE_NAME.${EXT^^}" ]; then
                IMAGE_FOUND=true
                break
            fi
        done

        if [ "$IMAGE_FOUND" = false ]; then
            rm -f "$THM_FILE"
            echo "Deleted $THM_FILE"
        fi
    done

    echo "Deleting empty folders from $MOUNTPOINT..."
    # Delete empty directories without deleting the mount point
    find "$MOUNTPOINT" -mindepth 1 -type d -empty -delete
}

# Function to authenticate with Immich server and get JWT token
authenticate_immich() {
    echo "Authenticating with Immich server..."
    AUTH_RESPONSE=$(curl -s -X POST "$IMMICH_SERVER_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"'"$IMMICH_USERNAME"'","password":"'"$IMMICH_PASSWORD"'"}')
    TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.accessToken')
    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo "Error: Authentication failed. Please check your credentials."
        exit 1
    fi
    echo "Authentication successful."
}

# Function to upload images to Immich server
upload_images_to_immich() {
    echo "Uploading images to Immich server..."
    find "$TEMP_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
        -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.heic" \
        -o -iname "*.heif" -o -iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" \
        -o -iname "*.dng" \) | while read -r IMAGE_FILE; do
        echo "Uploading $IMAGE_FILE..."

        # Extract DEVICE_ID from the file path
        # Remove the TEMP_FOLDER prefix
        RELATIVE_PATH="${IMAGE_FILE#"$TEMP_FOLDER"/}"
        # Extract the first component of the relative path, which is the SERIAL
        DEVICE_ID="${RELATIVE_PATH%%/*}"

        # Generate deviceAssetId (unique ID for the asset on the device)
        DEVICE_ASSET_ID=$(uuidgen)

        # Get file creation and modification times in ISO 8601 format
        FILE_CREATED_AT=$(stat -c %w "$IMAGE_FILE")
        FILE_MODIFIED_AT=$(stat -c %y "$IMAGE_FILE")

        # If birth time is not available, use modification time
        if [ "$FILE_CREATED_AT" = "-" ]; then
            FILE_CREATED_AT="$FILE_MODIFIED_AT"
        fi

        # Format timestamps to ISO 8601
        FILE_CREATED_AT=$(date -Iseconds -d "$FILE_CREATED_AT")
        FILE_MODIFIED_AT=$(date -Iseconds -d "$FILE_MODIFIED_AT")

        # Determine asset type
        ASSET_TYPE="IMAGE"

        # Upload to Immich server and capture HTTP status code
        HTTP_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$IMMICH_SERVER_URL/api/asset/upload" \
            -H "Authorization: Bearer $TOKEN" \
            -F "assetData=@$IMAGE_FILE" \
            -F "deviceAssetId=$DEVICE_ASSET_ID" \
            -F "deviceId=$DEVICE_ID" \
            -F "fileCreatedAt=$FILE_CREATED_AT" \
            -F "fileModifiedAt=$FILE_MODIFIED_AT" \
            -F "isFavorite=false" \
            -F "assetType=$ASSET_TYPE")

        # Extract the body and the status
        HTTP_STATUS="${HTTP_RESPONSE##*HTTPSTATUS:}"
        HTTP_BODY="${HTTP_RESPONSE%HTTPSTATUS:*}"

        # Check if the upload was successful
        if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
            echo "Upload successful. Deleting $IMAGE_FILE from temp folder."
            rm -f "$IMAGE_FILE"
        else
            echo "Upload failed with status $HTTP_STATUS. Response: $HTTP_BODY"
            echo "File $IMAGE_FILE was not deleted."
        fi
    done
    echo "Image upload process completed."
}

# ============================
# Main Function
# ============================

main() {
    # List of image file extensions (case-insensitive)
    IMAGE_EXTENSIONS=(
        "jpg" "jpeg" "png" "gif" "bmp" "tiff" "heic" "heif"
        "raw" "cr2" "nef" "dng"
    )

    # Temporary folder to copy images to
    TEMP_FOLDER="/tmp/sdcard_images"

    # Read paths to configuration files from environment variables
    read_config_var "IMMICH_SERVER_URL_FILE" "IMMICH_SERVER_URL" "server URL"
    read_config_var "IMMICH_USERNAME_FILE" "IMMICH_USERNAME" "username"
    read_config_var "IMMICH_PASSWORD_FILE" "IMMICH_PASSWORD" "password"

    # Read SD card serial numbers from environment variable
    if [ -z "$SD_CARD_SERIALS" ]; then
        echo "Error: SD_CARD_SERIALS environment variable is not set. Please set it with space-separated serial numbers."
        exit 1
    fi

    # Convert SD_CARD_SERIALS to an array
    IFS=' ' read -r -a SD_SERIALS_ARRAY <<< "$SD_CARD_SERIALS"

    # Create the temporary folder if it doesn't exist
    mkdir -p "$TEMP_FOLDER"

    # List all removable devices that are currently mounted
    lsblk -nr -o NAME,MOUNTPOINT,RM | while read -r NAME MOUNTPOINT RM; do
        if [[ "$RM" == "1" && -n "$MOUNTPOINT" ]]; then
            DEVICE="/dev/$NAME"

            # Get the serial number of the device using udevadm
            SERIAL=$(udevadm info --query=property --name="$DEVICE" | grep '^ID_SERIAL=' | cut -d'=' -f2)

            # Check if the serial is in the list using a loop (avoids SC2199 and SC2076)
            SERIAL_FOUND=false
            for s in "${SD_SERIALS_ARRAY[@]}"; do
                if [ "$s" = "$SERIAL" ]; then
                    SERIAL_FOUND=true
                    break
                fi
            done

            if [ "$SERIAL_FOUND" = true ]; then
                echo "$DEVICE (serial: $SERIAL) is mounted at $MOUNTPOINT"
                copy_and_delete_images "$SERIAL" "$MOUNTPOINT"
            else
                echo "Skipping $DEVICE (serial: $SERIAL)"
            fi
        fi
    done

    echo "All images have been copied to $TEMP_FOLDER, and source files and empty folders have been deleted from the SD cards."

    # Authenticate with Immich server
    authenticate_immich

    # Upload images to Immich server
    upload_images_to_immich

    # Delete any empty directories within TEMP_FOLDER, including TEMP_FOLDER if it's empty
    find "$TEMP_FOLDER" -type d -empty -delete
    echo "Empty folders within $TEMP_FOLDER have been deleted."
}

# ============================
# Execute Main Function
# ============================

main
