#!/usr/bin/env bash

set -o errexit -o errtrace -o nounset -o pipefail

source './deps/includes/src/comment/license/comment.license-gpl3.inc'
source './deps/includes/src/declare/declare.color.inc'
source './deps/includes/src/declare/declare.exit-codes.inc'

readonly VERSION=0.1.1

: "${GITHUB_TOKEN?Environmental variable 'GITHUB_TOKEN' must be set to autheticate against the Github API}"

# ==========================================================================
# @TODO: What to do with merge conflicts? Can we grab things from the git-split?
# @TODO: How to make things granular? Store the MR name/numbers and/or commit hashes?
# ==========================================================================
github-merge-all-upstream-pull-requests () {

    addRemotes () {
        local -a aRemotes=()
        local -i iIndex
        local sDirectory sProject sRemote sRemotes sSourceUrl

        readonly sSourceUrl=${1?Four parameters required: <source-domain> <source-repo> <working-directory> <remotes>}
        readonly sProject=${2?Four parameters required: <source-domain> <source-repo> <working-directory> <remotes>}
        readonly sDirectory=${3?Four parameters required: <source-domain> <source-repo> <working-directory> <remotes>}
        readonly sRemotes=${4?Four parameters required: <source-domain> <source-repo> <working-directory> <remotes>}

        readonly aRemotes=( $(echo "${sRemotes}" | cut -d ':' -f 1 | sort -u) )

        echo " =====> Found ${#aRemotes[@]} remotes for ${sProject}"

        for iIndex in "${!aRemotes[@]}";do

            sRemote="${aRemotes[${iIndex}]}"
            sUrl="git@${sSourceUrl}:${sRemote}/${sProject}.git"

            echo -e " -----> ${sRemote}\t\t($((iIndex+1)) of ${#aRemotes[@]})"
            git --git-dir="${sDirectory}/.git" --work-tree="${sDirectory}" remote add "${sRemote}" "${sUrl}"
        done
    }

    fetchPullRequestPages () {
        local -i iPage
        local bNext
        local sApiUrl sDirectory

        readonly sDirectory=${1?Two parameters required: <directory> <api-url>}
        readonly sApiUrl=${2?Two parameters required: <directory> <api-url>}

        iPage=0
        bNext=true

        echo " =====> Fetching page list"
        # @FIXME: Rather than itterating the ENTIRE LIST, just grab the `rel="last"` from the first request!
        while [[ "${bNext}" == true ]]; do
            let iPage=iPage+1
            ( curl -u "${GITHUB_TOKEN}:x-oauth-basic" -s -o /dev/null -D - "${sApiUrl}/pulls?per_page=100&page=${iPage}" | grep "next" ) \
            && bNext=true \
            || bNext=false
        done

        echo " =====> Fetching pages"
        while [[ "${iPage}" -gt 0 ]]; do
            curl -u "${GITHUB_TOKEN}:x-oauth-basic" -sL -o "${sDirectory}/pulls-${iPage}.log" "${sApiUrl}/pulls?per_page=100&page=${iPage}"
            let iPage=iPage-1 || true
        done
    }

    fetchRemoteBranches () {
        local -a  aFailure=() aRemotes=()
        local -i iIndex
        local sDirectory sRemote sRemotes

        readonly sDirectory=${1?Two parameters required: <working-directory> <remotes>}
        readonly sRemotes=${2?Two parameters required: <working-directory> <remotes>}

        readonly aRemotes=( $(echo "${sRemotes}" | cut -d ':' -f 1 | sort -u) )

        echo " =====> Found ${#aRemotes[@]} remotes to fetch"

        for iIndex in "${!aRemotes[@]}";do
            sRemote="$(echo "${aRemotes[${iIndex}]}" | tr ':' '/')"

            echo -e " -----> Fetching ${sRemote}\t\t($((iIndex+1)) of ${#aRemotes[@]})"
            git --git-dir="${sDirectory}/.git" --work-tree="${sDirectory}" \
                fetch "${sRemote}" --no-tags --quiet \
            || aFailure+=("${sRemote}")
        done

        echo " =====> Fetch failures: ${#aFailure[@]}"
        echo -e "        ${aFailure[@]}"
    }

    mergeBranches () {
        local -a  aFailure=() aRemotes=()
        local -i iIndex
        local sDirectory sRemote sRemotes

        readonly sDirectory=${1?Two parameters required: <working-directory> <remotes>}
        readonly sRemotes=${2?Two parameters required: <working-directory> <remotes>}

        readonly aRemotes=( ${sRemotes} )

        echo " =====> Found ${#aRemotes[@]} branches to merge"

        for iIndex in "${!aRemotes[@]}";do
            sRemote="$(echo "${aRemotes[${iIndex}]}" | tr ':' '/')"

            echo -e " -----> Merging ${sRemote}\t\t($((iIndex+1)) of ${#aRemotes[@]})"

            { git --git-dir="${sDirectory}/.git" --work-tree="${sDirectory}" \
                merge "${sRemote}" --no-edit -s recursive -X patience  --quiet
            } || aFailure+=("${sRemote}")

            if [[ -f "${sDirectory}/.git/MERGE_HEAD" ]];then
                git --git-dir="${sDirectory}/.git" --work-tree="${sDirectory}" \
                    merge --abort
            fi
        done

        echo " =====> Merge failures: ${#aFailure[@]}"
        echo -e "        ${aFailure[@]}"
        # @TODO: Resolve conflicts
    }

    parseSourcesFromPage () {
        local sDirectory sRepo

        readonly sDirectory="${1?Two parameters required: <directory> <github-repo>}"
        readonly sRepo="${2?Two parameters required: <directory> <github-repo>}"

        cat "${sDirectory}/pulls-"* \
            | grep '"label": "' \
            | cut -d '"' -f 4 \
            | grep -v "${sRepo}" \
            | sort -u
    }


    usage () {
        echo "Retrieves all merge-requests for a given github repository and merges them to a local git repo."
        echo ""
        echo "Usage: $(basename "$0") [options] <github-repo>"
        echo ""
        echo "Where <repo> takes the shape 'vendor/project'"
        echo ""
        echo "Options:"
        echo "  -h|--help      Print this help dialogue and exit"
        echo "  -V|--version   Print the current version and exit"
    }


    main() {
        local sRepo sRepoUrl sSourceUrl

        readonly sRepo="${1?One parameter required: <github-repo> [working-directory] [github-domain]}"
        readonly sWorkingDirectory="${2:-/tmp}"
        readonly sSourceUrl="${3:-github.com}"

        mkdir -p "${sWorkingDirectory}/${sRepo}"

        # Checkout the upstream git repo
        git clone "git@${sSourceUrl}:${sRepo}.git" "${sWorkingDirectory}/${sRepo}/repo"

        # Grab all PR pages from the Github API
        fetchPullRequestPages "${sWorkingDirectory}/${sRepo}" "https://api.${sSourceUrl}/repos/${sRepo}"

        # Grab all remotes (git repo & source branch) from pages
        local sRemotes="$(parseSourcesFromPage "${sWorkingDirectory}/${sRepo}" "${sRepo}")"

        # Add a remote for each MR source
        addRemotes "${sSourceUrl}" "${sRepo##*/}" "${sWorkingDirectory}/${sRepo}/repo" "${sRemotes}"

        # Fetch each remote branch
        fetchRemoteBranches "${sWorkingDirectory}/${sRepo}/repo" "${sRemotes}"

        # Merge fetched remote branch into master
        mergeBranches "${sWorkingDirectory}/${sRepo}/repo" "${sRemotes}"

        # @TODO: Ad trap for cleanup
    }

    export PS4='\e[36;5;6m[$(basename $0):$(printf "%04d" $LINENO)]\e[0m '

    local sRepo # 'kelseyhightower/nocode'

    for opt in "${@}"; do
        case "$opt" in
            -h|--help)
                usage
                return 0
            ;;
            -V|--version)
                echo "${VERSION}"
                return 0
            ;;

            *)
                readonly sRepo="${1}"
                shift
            ;;
        esac
    done

    if [[ "${sRepo:-}" = "" ]];then
        echo 'One parameter required: <github-repo>' >> /dev/stderr
        return 1
    fi

    main "${sRepo}"
}

if [[ ${BASH_SOURCE[0]} != $0 ]]; then
    export -f github-merge-all-upstream-pull-requests
else
    github-merge-all-upstream-pull-requests "${@}"
    exit $?
fi

#EOF
