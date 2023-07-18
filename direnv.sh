#!/usr/bin/env bash

use_auto_op() {
    PWD=`pwd`
    echo "direnv+op: running ${PWD}/.envrc"

    envFiles=()

    # Getting the current directory
    if [[ "${PWD}" != */ ]]; then
        PWD="${PWD}/"
    fi

    # Is the user sourcing multiple dirs?
    if [[ ! -z "${DIRENV_USE_FILE}" ]]; then
        # Check if the file also in this folder
        if [[ -f "${PWD}${DIRENV_USE_FILE}" ]]; then
            envFiles+=("${PWD}${DIRENV_USE_FILE}")
        fi

        # Exit if the array is empty
        if [ ${#envFiles[@]} -eq 0 ]; then
            echo "direnv+op: skipping ${PWD}${DIRENV_USE_FILE} file not found"
            return
        fi
    else
        # First user-interaction, let's find all .env & .env-* files
        for f in $(ls -1 ${PWD}.env*); do
            if [[ $f =~ ^.*\/\.env(-.*)?$ ]]; then
                envFiles+=("$f")
            fi
        done

        # Exit if the array is empty
        if [ ${#envFiles[@]} -eq 0 ]; then
            echo "direnv+op: .env* files not found in ${PWD}"
            return
        fi

        # Ask the user to pick one if there are multiple files
        if [ ${#envFiles[@]} -gt 1 ]; then
            echo "direnv+op: multiple files found in ${PWD}:"
            PS3="Please select one: "
            select opt in "${envFiles[@]}"; do
                if [ "$opt" != "" ]; then
                    selEnvFile="$opt"
                    break
                fi
            done
        else
            selEnvFile="${envFiles[0]}"
        fi

        # Set the selected .env file as the current one
        export DIRENV_USE_FILE=`basename $selEnvFile`
    fi

    # check if $selEnvFile exists
    if [[ ! -f "${selEnvFile}" ]]; then
        echo "direnv+op: file ${selEnvFile} not found"
        return
    fi

    # Now we need to read its content
    echo "direnv+op: loading $selEnvFile"
    CONTENT=$(cat "$selEnvFile")

    # Using 1password to inject secrets
    if [[ $CONTENT =~ {{\ *op:\/\/ ]]; then
        CONTENT=$(echo "$CONTENT" | op inject)
    fi

    prevAWSProfile=$AWS_PROFILE

    # Exporting all the envs
    export $CONTENT

    # Let's assume the role if needed
    if [[ -z "${prevAWSProfile}" ]] || [[ "${prevAWSProfile}" != "${AWS_PROFILE}" ]]; then
        if [[ ! -z "${AWS_PROFILE}" ]]; then
            if [[ ! -z "${AWS_REGION}" ]]; then
                echo "direnv+op: assuming role ${AWS_PROFILE} in ${AWS_REGION}"
                IFS=' ' source assume ${AWS_PROFILE} --region=${AWS_REGION}
            else
                echo "direnv+op: assuming role ${AWS_PROFILE}"
                IFS=' ' source assume ${AWS_PROFILE}
            fi
            export _AWS_PROFILE=${AWS_PROFILE}
            unset AWS_PROFILE;
        fi
    fi
}