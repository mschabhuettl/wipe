#!/bin/bash

# Exit on error
set -e

# Function to print verbose messages
verbose() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}

# Function to print error messages
error_message() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Function to execute a command and check for success
execute_command() {
    local cmd="$1"
    verbose "Executing: $cmd"
    eval "$cmd"
    local status=$?
    if [ $status -ne 0 ]; then
        error_message "Command failed -> $cmd"
        exit 1
    fi
}

# Function to check NVMe sanitize status
check_nvme_sanitize() {
    local device="$1"
    while true; do
        output=$(nvme sanitize-log $device 2>/dev/null)
        local sprog=$(echo "$output" | awk '/Sanitize Progress/ {print $NF}')
        local sstat=$(echo "$output" | awk '/Sanitize Status/ {print $NF}')
        
        if [[ "$sprog" == "65535" && "$sstat" == "0x101" ]]; then
            verbose "Sanitize process for $device completed."
            verbose "Final Sanitize Status: SPROG=$sprog, SSTAT=$sstat"
            break
        elif [[ -z "$sprog" || -z "$sstat" ]]; then
            error_message "Sanitize log not providing expected values. Aborting."
            exit 1
        fi
        verbose "Waiting for sanitize process to complete on $device... (SPROG=${sprog:-unknown}, SSTAT=${sstat:-unknown})"
        sleep 5
    done
}

# Function to validate drive names and normalize NVMe names
normalize_drive() {
    local device="$1"
    if [[ "$device" =~ ^/dev/nvme[0-9]+$ ]]; then
        echo "$device"
    else
        error_message "Unsupported device format: $device. Only /dev/nvmeX is allowed."
        exit 1
    fi
}

validate_drive() {
    local device="$1"
    if [[ ! -e "$device" ]]; then
        error_message "Invalid device: $device does not exist."
        exit 1
    fi
}

# Function to list and select drives for secure erase
select_drives() {
    verbose "Listing available NVMe controller devices..."
    nvme list
    verbose "Note: Only controller devices like /dev/nvmeX are supported. Do NOT use namespaces like /dev/nvmeXn1."

    # Extract valid /dev/nvmeX controller device (1st column in `nvme list`)
    local example_device=$(nvme list | awk 'NR>1 && $1 ~ /^\/dev\/nvme[0-9]+$/ {print $1; exit}')

    read -p "Enter the target drive(s) (space-separated, e.g., $example_device): " -a selected_drives
}

# Secure erase for NVMe drives
secure_erase_nvme() {
    local device=$(normalize_drive "$1")
    
    execute_command "nvme format $device -s 2 -n 1 --force"
    execute_command "nvme sanitize $device -a start-crypto-erase"
    check_nvme_sanitize "$device"
    execute_command "nvme sanitize $device -a start-block-erase"
    check_nvme_sanitize "$device"
    execute_command "nvme format $device -s 2 -n 1 --force"
}

# Get user selection
select_drives

# Loop through selected drives and perform secure erase
for drive in "${selected_drives[@]}"; do
    drive=$(normalize_drive "$drive")
    validate_drive "$drive"
    secure_erase_nvme "$drive"
done

verbose "Secure erase completed successfully."