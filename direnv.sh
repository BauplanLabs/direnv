#!/usr/bin/env bash

AUTO_OP_CONFIG="${HOME}/.config/auto_op"
RED='\033[0;31m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
NOCOLOR='\033[0m'

use_auto_op() {
    PWD=`pwd`
    echo "direnv+op: running ${PWD}/.envrc"

    envFiles=()
    selEnvFiles=()

    # Getting the current directory
    if [[ "${PWD}" != */ ]]; then
        PWD="${PWD}/"
    fi

    # Fetching cached selection, if available
    if [[ -z "${AUTO_OP_FILE}" ]]; then
        # First time auto_op is called, let's hash the current directory
        AUTO_OP_HASH=`echo -n "$PWD" | shasum | awk '{print $1}'`
        AUTO_OP_FILE="${AUTO_OP_CONFIG}/${AUTO_OP_HASH}"

        # We now need to check if the file ${AUTO_OP_HASH} exists on ~/.config/auto_op
        if [[ -f "${AUTO_OP_FILE}" ]]; then
            # If it exists, we need to check if it's older than 4h
            FILE_AGE=$(($(date +%s) - $(stat -f%c "${AUTO_OP_FILE}")))
            if [[ $FILE_AGE -gt 14400 ]]; then
                # If it's older than 4h, we need to invalidate its content
                echo "direnv+op: invalidating session ${AUTO_OP_FILE}"
                rm "${AUTO_OP_FILE}"
            else
                # Parse the content of the file, fetch the line "env: " and get the string after it
                DIRENV_USE_FILE=$(cat "${AUTO_OP_FILE}" | grep "env: " | sed 's/env: //g')
                # Let's load the old file
                printf "${PURPLE}direnv+op: restoring \"${DIRENV_USE_FILE}\" from local cache${NOCOLOR}\n"
            fi
        else
            # Let's create the folder if it doesn't exist
            mkdir -p "${AUTO_OP_CONFIG}"
        fi
    fi

    # Exporting the hash
    export AUTO_OP_FILE=${AUTO_OP_FILE}

    # Is the user sourcing multiple dirs?
    if [[ ! -z "${DIRENV_USE_FILE}" ]]; then
        # Check if the file also in this folder
        if [[ -f "${PWD}${DIRENV_USE_FILE}" ]]; then
            selEnvFiles+=("${PWD}${DIRENV_USE_FILE}")
        fi

        # Exit if the array is empty
        if [ ${#selEnvFiles[@]} -eq 0 ]; then
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
            printf "${YELLOW}direnv+op: multiple files found in ${PWD}:\n"
            PS3="Please select one: "
            select opt in "${envFiles[@]}"; do
                if [ "$opt" != "" ]; then
                    selEnvFiles=("$opt")
                    break
                fi
            done
            printf ${NOCOLOR}
        else
            selEnvFiles=("${envFiles[0]}")
        fi

        # Set the selected .env file as the current one
        export DIRENV_USE_FILE=`basename ${selEnvFiles[0]}`

        # Let's freeze the selection
        echo -e "dir: ${PWD}\nenv: ${DIRENV_USE_FILE}" > "${AUTO_OP_FILE}.tmp"

        # And write it only if needed (otherwise we will trigger the watch_file function below)
        if ! cmp -s "${AUTO_OP_FILE}.tmp" "${AUTO_OP_FILE}"; then
            mv "${AUTO_OP_FILE}.tmp" "${AUTO_OP_FILE}"
        else
            rm "${AUTO_OP_FILE}.tmp"
        fi
    fi

    # if AUTO_OP_FILE exist, print ecgo
    if [[ -f "${AUTO_OP_FILE}" ]]; then
        printf "${PURPLE}direnv+op: use \"unload\" to load another .env file${NOCOLOR}\n"

        # Users can reset the configuration
        export_alias unload "rm ${AUTO_OP_FILE}"

        # Now we can watch this file to reload direnv when it will be deleted
        watch_file "${AUTO_OP_FILE}"
    fi

    # check if $selEnvFile exists
    if [ ${#selEnvFiles[@]} -eq 0 ]; then
        echo "direnv+op: file ${selEnvFile} not found"
        return
    fi

    CONTENT=""

    for selEnvFile in "${selEnvFiles[@]}"; do
        # Now we need to read its content
        echo "direnv+op: loading $selEnvFile"
        CONTENT="${CONTENT} $(cat "$selEnvFile")"
    done

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

export_alias() {
  local name=$1
  shift
  local alias_dir=$PWD/.direnv/aliases
  local target="$alias_dir/$name"
  local oldpath="$PATH"
  mkdir -p "$alias_dir"
  if ! [[ ":$PATH:" == *":$alias_dir:"* ]]; then
    PATH_add "$alias_dir"
  fi

  echo "#!/usr/bin/env bash" > "$target"
  echo "PATH=$oldpath" >> "$target"
  echo "$@" >> "$target"
  chmod +x "$target"
}
