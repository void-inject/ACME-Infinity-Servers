#!/bin/bash

set -o pipefail
source provision.sh

CHOICE="${1}"
LOG="/var/log/lab-install.log"

if [[ -n "${DEBUG}" ]] && [[ "${DEBUG}" = "true" ]]; then
    LOG=/dev/stderr
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: Please run using sudo permissions."
    exit 1
fi

if ! systemctl is-active --quiet docker; then
    echo "Docker service appears to not be running. Start it using:"
    echo "$ sudo systemctl start docker"
    exit 1
fi

if ! command -v docker-compose &>/dev/null && ! command -v docker compose &>/dev/null; then
    echo "Docker Compose is not installed. Install it following these instructions:"
    echo "https://docs.docker.com/compose/install/"
    exit 1
fi

if [[ ! -f "${LOG}" ]]; then
    touch "${LOG}"
    chown "${SUDO_USER}:${SUDO_USER}" "${LOG}"
fi

wait() {
    local pid=$1
    local message=$2
    local spinner="/-\|"
    local i=0

    echo -n "${message} "
    while kill -0 "${pid}" &>/dev/null; do
        printf "\b%s" "${spinner:i++%${#spinner}:1}"
        sleep 0.1
    done
    echo
}

images_built() {
    local expected_containers
    local built_images

    expected_containers=$(grep -c container_name docker-compose.yml)
    built_images=$(docker images | grep -c lab-)

    [[ "${built_images}" -eq "${expected_containers}" ]]
}

status() {
    local expected_containers
    local running_containers

    expected_containers=$(grep -c container_name docker-compose.yml)
    running_containers=$(docker ps | grep -c lab-)

    [[ "${running_containers}" -eq "${expected_containers}" ]]
}

deploy() {
    echo
    echo "==== Deployment Started ===="

    if ! images_built; then
        echo "This process can take a few minutes to complete."
        echo "Start Time: $(date "+%T")" >>"${LOG}"

        if [[ -z "${DEBUG}" ]]; then
            echo "Monitor progress using: tail -f ${LOG}"
        fi

        docker build -f machines/Dockerfile-base -t lab_base . &>>"${LOG}"
        docker compose build --parallel &>>"${LOG}" &
        wait "$!" "Building and deploying the lab..."
        docker compose up --detach &>>"${LOG}"

        if status; then
            echo "OK: All containers are running. Performing post-provisioning steps..." | tee -a "${LOG}"
            sleep 25
            if check_post_actions &>>"${LOG}"; then
                echo "OK: Lab is up and provisioned." | tee -a "${LOG}"
            else
                echo "Error: Post-provisioning steps failed." | tee -a "${LOG}"
            fi
        else
            echo "Error: Not all containers are running. Check the log file: ${LOG}"
        fi
    else
        docker compose up --detach &>>"${LOG}"
        sleep 5
        if status; then
            echo "Lab is up."
        else
            echo "Lab is down. Try rebuilding."
        fi
    fi
    echo "End Time: $(date "+%T")" >>"${LOG}"
}

teardown() {
    echo
    echo "==== Teardown Started ====" | tee -a "${LOG}"
    docker compose down --volumes
    echo "OK: Lab has shut down."
}

clean() {
    echo
    echo "==== Cleanup Started ===="
    docker compose down --volumes --rmi all &>/dev/null &
    wait "$!" "Cleaning up the lab..."

    docker system prune -a --volumes -f &>/dev/null &
    wait "$!" "Removing unused Docker resources..."

    [[ -f "${LOG}" ]] && >"${LOG}"
    echo "OK: Lab environment cleaned up."
}

rebuild() {
    clean
    deploy
}

case "${CHOICE}" in
deploy)
    deploy
    ;;
teardown)
    teardown
    ;;
clean)
    clean
    ;;
rebuild)
    rebuild
    ;;
status)
    if status; then
        echo "Lab is up."
    else
        echo "Lab is down."
        exit 1
    fi
    ;;
*)
    echo "Usage: $(basename "$0") deploy | teardown | rebuild | clean | status"
    ;;
esac
