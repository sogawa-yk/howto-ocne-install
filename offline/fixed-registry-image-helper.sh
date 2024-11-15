#!/bin/bash
#
# Copyright (c) 2019-2023 Oracle and/or its affiliates. All rights reserved.
# Licensed under the GNU General Public License Version 3 as shown at https://www.gnu.org/licenses/gpl-3.0.txt.

set -o nounset
set -o pipefail
set -o errtrace

# variables
TO_REGISTRY=
FROM_REGISTRY=container-registry.oracle.com/olcne
OLCNE_DIRECTORY=/etc/olcne/utils/
USELOCAL=0
MODULE_VERSION=
MODULE_NAME=
DRY_RUN=0

# allModules lists all the modules containing "container-images" in the module config file.
# If --module <module-name> is not specified, allModules is used to derive all the modules containing container-images
function allModules {
   allMods=$(ls ${OLCNE_DIRECTORY} | tr '\n' ' ' | sed 's/\bhelm[^ ]*//g' | sed "s|kubernetes| |" | sed "s|oci-ccm| |" | sed "s|node| |"| sed "s|gluster| |")
   echo ${allMods}
}

function exit_trap {
    local rc=$?
    local lc="$BASH_COMMAND"

    if [[ $rc -ne 0 ]]; then
        echo "Command [$lc] exited with code [$rc]"
    fi
}

trap exit_trap EXIT

function pull {
    registry=$1
    image=$2
    echo ">> Pulling image: ${registry}/${image}"
    if [ "${DRY_RUN}" -eq 0 ]; then
      podman pull "${registry}/${image}"
    fi
}

function tag {
    registry=$1
    image=$2
    echo ">> Tagging image: ${registry}/${image} to ${TO_REGISTRY}/${image}"
    if [ "${DRY_RUN}" -eq 0 ]; then
      podman tag "${registry}/${image}" "${TO_REGISTRY}/${image}"
    fi
}

function push {
    image=$1

    echo ">> Pushing image: ${TO_REGISTRY}/${image}"
    if [ "${DRY_RUN}" -eq 0 ]; then
      podman push "${TO_REGISTRY}/${image}"
    fi
}

function getFromModule {
    moduleFile=${1}
    moduleVersion=${2}
    fieldName=${3}
    suffix=${4} ### optional suffix - to specify per image container-registry
    if [[ "${suffix}" != "" ]]; then
      suffix=" ${suffix}"
    fi
    if [[ "${yqOld}" == "${yqMin}" ]]; then
        grep 'versions:' "${moduleFile}" -A1000 | grep END_VERSION_BLOCK -B 1000  | yq e ".versions.\"${moduleVersion}\".${fieldName}" - | sed "s|$|${suffix}|"
    else
        # yq-3.4
        grep 'versions:' "${moduleFile}" -A1000 | grep END_VERSION_BLOCK -B 1000  | yq r - versions.["${moduleVersion}"].${fieldName} | sed "s|$|${suffix}|"
    fi
}

function getImagesFromModule {
    moduleFile=$1
    moduleVersion=$2
    getFromModule "${moduleFile}" "${moduleVersion}" "container-images" ""
    getFromModule "${moduleFile}" "${moduleVersion}" "extra-images" ""
}

function getKubernetesImages {
    kubernetesVersion=$1
    getModuleImages "kubernetes" "${kubernetesVersion}"

    # TODO: We need to handle these images inside the module definition but not pull them down on every node
    function 1.17.9_extra_images {
        echo "kubernetes-dashboard: v1.10.1-2"
        echo "flannel: v0.12.0"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0"
    }
    function 1.18.10_extra_images {
        echo "kubernetes-dashboard: v2.0.3"
        echo "flannel: v0.12.0"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0"
    }
    function 1.18.18_extra_images {
        echo "kubernetes-dashboard: v2.0.3-1"
        echo "flannel: v0.12.0-1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.20.6_extra_images {
        echo "kubernetes-dashboard: v2.1.0"
        echo "flannel: v0.13.0"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.20.11_extra_images {
        echo "kubernetes-dashboard: v2.1.0"
        echo "flannel: v0.13.0"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.21.6_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.21.14_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.21.14-3_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.22.8_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.22.14_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.22.16_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.23.7_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.23.11_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    function 1.23.14_extra_images {
        echo "kubernetes-dashboard: v2.3.1"
        echo "flannel: v0.14.1"
        echo "nginx: 1.17.7"
        echo "externalip-webhook: v1.0.0-1"
    }
    case "${kubernetesVersion}" in
        1.17.9)
            1.17.9_extra_images
        ;;

        1.18.10)
            1.18.10_extra_images
        ;;

        1.18.18)
            1.18.18_extra_images
        ;;

        1.20.6)
            1.20.6_extra_images
        ;;
        1.20.11)
            1.20.11_extra_images
        ;;
        1.21.6)
            1.21.6_extra_images
        ;;
        1.21.14)
            1.21.14_extra_images
        ;;
        1.21.14-3)
            1.21.14-3_extra_images
        ;;
        1.22.8)
            1.22.8_extra_images
        ;;
        1.22.14)
            1.22.14_extra_images
        ;;
        1.22.16)
            1.22.16_extra_images
        ;;
        1.23.7)
            1.23.7_extra_images
        ;;
        1.23.11)
            1.23.11_extra_images
        ;;
        1.23.14)
            1.23.14_extra_images
        ;;

        # All images
        *)
            if [[ "${kubernetesVersion}" == *"."* ]]; then
                echo "[ERROR] cannot find version ${kubernetesVersion} in ${moduleName} module" >&2
                exit 1
            fi
            1.17.9_extra_images
            1.18.10_extra_images
            1.18.18_extra_images
            1.20.6_extra_images
            1.20.11_extra_images
            1.21.6_extra_images
            1.21.14_extra_images
	    1.21.14-3_extra_images
            1.22.8_extra_images
            1.22.14_extra_images
	    1.22.16_extra_images
	    1.23.7_extra_images
            1.23.11_extra_images
	    1.23.14_extra_images
        ;;
    esac
}

function getModuleImages {
    moduleName=$1
    moduleVersion=$2
    if [[  "${moduleName}" == "operator-lifecycle-manager" ]]; then
        moduleName="olm"
    fi
    FILES=$(find ${OLCNE_DIRECTORY} -name "${moduleName}".yaml)
    if [ -z "$FILES" ] || [  "$FILES" == "" ] || [ "${#FILES}" == "0" ]; then
        echo "[ERROR] cannot find ${moduleName} module file ${moduleName}.yaml in $OLCNE_DIRECTORY. Supported modules: kubernetes oci-ccm $(allModules)" >&2
        exit 1
    fi

    for filename in $FILES; do
        VERS=$(getImagesFromModule "${filename}" "${moduleVersion}" | awk 'NF && !seen[$0]++' -)
    done
    if echo "$VERS" | grep -w "null" ; then
      echo "[WARN] ${moduleName} module ${moduleVersion} does NOT have container images" >&2
    fi
    echo "$VERS"
}

function getOciCcmImagesForVersion {
    moduleFile=$1
    moduleVersion=$2
    oci_registry=$(getFromModule "${moduleFile}" "${moduleVersion}" "oci-registry" "")
    ccm_registry=$(getFromModule "${moduleFile}" "${moduleVersion}" "ccm-registry" "")
    getFromModule "${moduleFile}" "${moduleVersion}" "oci-container-images" "${oci_registry}"
    getFromModule "${moduleFile}" "${moduleVersion}" "ccm-container-images" "${ccm_registry}"
}

function getOciCcmImagesFromModule {
    moduleFile=$1
    moduleVersion=$2

    if [[ "${moduleVersion}" == "*" ]]; then
        versions=$(getFromModule "${moduleFile}" "*" "chart-version" "")
        list=(${versions//\n/ })
        for ver in "${list[@]}"; do
          getOciCcmImagesForVersion "${moduleFile}" "${ver}"
        done
    else
      getOciCcmImagesForVersion "${moduleFile}" "${moduleVersion}"
    fi
}

function getOciCcmImages {
    ociccmVersion=$1
    FILES=$(find ${OLCNE_DIRECTORY} -name oci-ccm.yaml)
    if [ -z "$FILES" ] || [  "$FILES" == "" ] || [ "${#FILES}" == "0" ]; then
        echo "[ERROR] cannot find ${moduleName} module file ${moduleName}.yaml in $OLCNE_DIRECTORY" >&2
        exit 1
    fi
    for filename in $FILES; do
        VERS=$(getOciCcmImagesFromModule "${filename}" "${ociccmVersion}" | awk 'NF && !seen[$0]++' -)
    done
    echo "$VERS"
}

function getImages {
    all_images_string="*"

    module="${1:-ALL}"
    moduleVersion="${2:-${all_images_string}}"
    if [[ "${module}" == "*" ]]; then
        module="ALL"
    fi

    case ${module} in
        kubernetes)
            getKubernetesImages "${moduleVersion}"
            ;;
        oci-ccm)
            getOciCcmImages "${moduleVersion}"
            ;;
        ALL)
            getKubernetesImages "${moduleVersion}"
            all_modules=($(allModules))
            for mod in "${all_modules[@]}"; do
                getModuleImages "${mod}" "${moduleVersion}"
            done
            getOciCcmImages "${moduleVersion}"
            ;;
        *)
            getModuleImages "${module}" "${moduleVersion}"
            ;;
    esac
}

yqMin="4.1"
yqOld="${yqMin}"

function check {
    echo "Checking if podman is installed ..."
    if ! podman --help > /dev/null; then
        echo "[ERROR] podman is not install ... please install podman"
        exit 1
    fi

    echo "Checking if yq is installed ..."
    if ! yq --help > /dev/null; then
        echo "[ERROR] yq is not install ... please install yq"
        exit 1
    fi
    yqVer=$(yq --version | awk '{print $NF}' | sed 's/^v//')
    yqOld=$(printf "${yqVer}"'\n'"${yqMin}"'\n' | sort -V | head -n1)
}

function usage {
    echo "This script is to help pulling container images from default container-registry.oracle.com to a local repo" >&2
    echo "usage: " >&2
    echo "  $0 --to registry [--local --from registry --module <MODULE NAME> --version <MODULE VERSION>]" >&2
    exit 1
}

function main {
    # Check the system to fail early
    check

    # 失敗したイメージを記録するファイルを初期化
    > failed.txt

    # Load all local images
    if [ "$USELOCAL" -eq 1 ]; then
        if ls /usr/local/share/kubeadm/*.tar &> /dev/null; then
            find /usr/local/share/kubeadm/*.tar -print0 | xargs -0 | xargs -n1 podman load -i
        fi
        if ls /usr/local/share/olcne/*.tar &> /dev/null; then
            find /usr/local/share/olcne/*.tar -print0 | xargs -0 | xargs -n1 podman load -i
        fi
    fi

    images=$(getImages "${MODULE_NAME}" "${MODULE_VERSION}")
    while IFS= read -r imageInfo ; do
        item=(${imageInfo// / })
        if [ -z "${item+defined}" ] || [ -z "${item}" ] ; then
            echo "[ERROR] cannot find container images ${MODULE_NAME} ${MODULE_VERSION}" >&2
            exit 1
        fi
        imageName="${item[0]}"
        imageTag=""
        if [ "${#item[@]}" -ge 2 ]; then
            imageTag="${item[1]}"
        else
            if [[ "${imageName}" != "null" ]]; then
              echo "[WARN] ${imageName} does not have image tag" >&2
            fi
        fi
        registry="${FROM_REGISTRY}"
        if [ "${#item[@]}" -eq 3 ]; then
            registry="${item[2]}"
        fi
        success=false

        if [[ "${imageName}" != "null" ]]; then
            for i in {1..10}; do
                if [ "$USELOCAL" -eq 0 ]; then
                    pull "${registry}" "${imageName}${imageTag}"
                    if [[ $? -ne 0 ]]; then
                        sleep 30
                        continue
                    fi
                fi

                tag "${registry}" "${imageName}${imageTag}"
                if [[ $? -ne 0 ]]; then
                    sleep 30
                    continue
                fi

                push "${imageName}${imageTag}"
                if [[ $? -ne 0 ]]; then
                    sleep 30
                    continue
                fi

                success=true
                break
            done
            if [[ "${success}" == "false" ]]; then
                echo "[ERROR] Failed to manage image [${imageName}${imageTag}]"
                echo "${registry}/${imageName}${imageTag}" >> failed.txt
                continue
            fi
        fi
    done <<< "${images}"

    if [ -s failed.txt ]; then
        echo "[WARNING] Some images failed to process. Check failed.txt for details"
        echo "[SUCCESS] Remaining images pushed to [${TO_REGISTRY}]"
    else
        echo "[SUCCESS] All images pushed to [${TO_REGISTRY}]"
        rm -f failed.txt
    fi
}

# MAIN
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --to )
            TO_REGISTRY=$2
            if [ -z "${TO_REGISTRY}" ]; then
                echo "[ERROR] Please provide a valid local registry location"
                exit 1
            fi
            shift # shift past argument
            shift # shift past value
        ;;
        --from )
            FROM_REGISTRY="${2:-${REGISTRY}}"
            shift # shift past argument
            shift # shift past value
        ;;
        --module )
            MODULE_NAME="${2}"
            shift # shift past argument
            shift # shift past value
        ;;
        --version )
            MODULE_VERSION="${2}"
            shift # shift past argument
            shift # shift past value
        ;;
        --local )
            USELOCAL=1
            shift # shift past argument
        ;;
        --dry-run )
            DRY_RUN=1
            shift # shift past argument
        ;;
        --module-dir )
            OLCNE_DIRECTORY="${2}"
            shift # shift past argument
            shift # shift past value
        ;;
        -h | --help )
            usage
            exit
        ;;
        *) # unknown option
            echo "[ERROR] unknown argument: ${key}"
            usage
            exit 1
        ;;
    esac
done

main
