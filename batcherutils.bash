# Utility functions

################################################################################
# BSD 3-Clause License
#
# Copyright (c) 2023, maharjun
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
################################################################################

################################################################################
# Replaces job IDs in a comma-separated list of dependencies with new IDs defined
# in an associative array.
#
# Usage:
#   new_dependency_string=$(replace_jobids_in_dependency <assoc_array_name> <dependency_string>)
#
# Arguments:
#   $1: Name of associative array for replacement. This array must map old IDs to
#       the new IDs. In case a mapping does not exist, the corresponding ID is not
#       replaced
#   $2: SLURM dependency string (e.g. afterok:1234:1235,afterany:1934). NOTE: only
#       comma separated strings supported. ? separated strings will fail with an
#       error
#
# Returns:
#   String of updated dependencies with new job IDs.
################################################################################
replace_jobids_in_dependency() {
    declare -a dependency_list
    declare -a new_dependency_list
    declare -a dep_parts

    if [[ -z "$1" ]]; then
        echo "Specify the name of the replacement associative array" >&2
        exit 1
    else
        declare -n _utils_old_id_to_new_id_map=$1
    fi
    # echo "Dependency_map: " >&2
    # printf "%s\n" "${!_utils_old_id_to_new_id_map[@]}" "${_utils_old_id_to_new_id_map[@]}" | pr -2t  >&2

    dep_string=$2
    if [[ dep_string =~ *\?* ]]; then
        echo "Cannot process question delimited dependencies for replacement" >&2
        exit 1
    fi

    IFS=',' read -ra dependency_list <<< "$dep_string"

    for dep_line in "${dependency_list[@]}"; do

        dep_parts=()
        IFS=':' read -ra dep_parts <<< "$dep_line"
        
        dependency_type="${dep_parts[0]}"
        new_dep_parts=("$dependency_type")
        
        for i in $(seq 1 $(( ${#dep_parts[@]} - 1 ))); do
            dep_part="${dep_parts[$i]}"
            if [[ ${_utils_old_id_to_new_id_map[$dep_part]} ]]; then
                new_dep_parts+=("${_utils_old_id_to_new_id_map[$dep_part]}")
            else
                new_dep_parts+=("$dep_part")
            fi
        done
        
        new_dep_line=$(IFS=':'; echo "${new_dep_parts[*]}")
        new_dependency_list+=("$new_dep_line")
    done
    echo "$(IFS=','; echo "${new_dependency_list[*]}")"
}

################################################################################
# This function aids in getting the next available pseudo job ID by reading and incrementing
# the value stored in a file located at `${HOME}/.pseudo_job_id`. It utilizes a lock file
# at `${HOME}/.pseudo_job_id_lock` to ensure safe concurrent access to the pseudo job ID file.
#
# Usage:
#   pseudo_job_id=$(inc_pseudo_job_id)
################################################################################
inc_pseudo_job_id() {
    local file_path
    local lock_path
    local current_pseudo_job_id

    file_path="${HOME}/.pseudo_job_id"
    lock_path="${HOME}/.pseudo_job_id_lock"

    # Create the lock file if it doesn't exist
    if [[ ! -e "${lock_path}" ]]; then
        touch "${lock_path}"
    fi

    # Acquire the lock with a 5-second timeout before reading and modifying the file
    if (flock -x -w 15 200); then
        # If the file doesn't exist, create it and initialize it to 1
        if [[ ! -e "${file_path}" ]]; then
            echo "1" > "${file_path}"
        fi

        # Read the contents of the file
        current_pseudo_job_id=$(cat "${file_path}")

        # Increment the contents of the file
        echo $((current_pseudo_job_id + 1)) > "${file_path}"
        echo "$current_pseudo_job_id"
    else
        echo "Failed to acquire lock within 5 seconds, exiting."
        exit 1
    fi 200>"${lock_path}"
}