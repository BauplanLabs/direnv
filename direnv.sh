#!/usr/bin/env bash

use_auto_op() {
    OLDPWD=${1:-$OLDPWD}
    echo "direnv+auto-op: running ${OLDPWD}/.envrc"

    envFiles=()


    # Getting the current directory
    RC_PATH=$OLDPWD
    if [[ "${RC_PATH}" != */ ]]; then
    RC_PATH="${RC_PATH}/"
    fi

    # Is the user sourcing multiple dirs?
    if [[ ! -z "${DIRENV_USE_FILE}" ]]; then
    # Check if the file also in this folder
    if [[ -f "${RC_PATH}${DIRENV_USE_FILE}" ]]; then
        envFiles+=("${RC_PATH}${DIRENV_USE_FILE}")
    fi

    # Exit if the array is empty
    if [ ${#envFiles[@]} -eq 0 ]; then
        echo "direnv+auto-op: skipping ${RC_PATH}${DIRENV_USE_FILE} file not found"
        return
    fi
    else
    # First user-interaction, let's find all .env & .env-* files
    for f in $(ls -1 ${RC_PATH}.env*); do
        if [[ $f =~ ^.*\/\.env(-.*)?$ ]]; then
        envFiles+=("$f")
        fi
    done

    # Exit if the array is empty
    if [ ${#envFiles[@]} -eq 0 ]; then
        echo "direnv+auto-op: .env* files not found in ${RC_PATH}"
        return
    fi

    # Ask the user to pick one if there are multiple files
    if [ ${#envFiles[@]} -gt 1 ]; then
        echo "direnv+auto-op: multiple files found in ${RC_PATH}:"
        PS3="Please select one: "
        select opt in "${envFiles[@]}"; do
        if [ "$opt" != "" ]; then
            selFile="$opt"
            break
        fi
        done
    else
        selFile="${envFiles[0]}"
    fi

    # Set the selected .env file as the current one
    export DIRENV_USE_FILE=`basename $selFile`
    fi

    # check if $selFile exists
    if [[ ! -f "${selFile}" ]]; then
    echo "direnv+auto-op: file ${selFile} not found"
    exit 0
    fi

    # Now we need to read its content
    echo "direnv+auto-op: loading $selFile"
    CONTENT=$(cat "$selFile")

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
        echo "direnv+auto-op: assuming role ${AWS_PROFILE} in ${AWS_REGION}"
        IFS=' ' source assume ${AWS_PROFILE} --region=${AWS_REGION}
        else
        echo "direnv+auto-op: assuming role ${AWS_PROFILE}"
        IFS=' ' source assume ${AWS_PROFILE}
        fi
        export _AWS_PROFILE=${AWS_PROFILE}
        unset AWS_PROFILE;
    fi
    fi
}