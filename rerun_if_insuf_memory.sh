#!/bin/bash

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
# This script is designed to be called from within an SBATCH script. Note that it
# SHOULD NOT be run using sbatch command directly. It checks if the node running
# the job has enough available memory to execute the tasks. If there isn't enough
# memory available, the script creates a new job with the same parameters as the
# current job, excluding the current node. The script then updates the dependencies
# of any dependent jobs to use the new job ID instead of the current job ID.
#
# Usage:
#   rerun_if_insuf_memory.sh [arguments to the parent sbatch script]
#
# Arguments:
#   args: Any additional arguments required by the main SBATCH script.
#
# In-script Parameters:
# 
# SYSTEM_MEMORY
#
# The script uses the following SLURM environment variables:
#   - SLURM_CPUS_PER_TASK
#   - SLURM_TASKS_PER_NODE
#   - SLURM_JOB_NUM_NODES
#   - SLURM_JOB_PARTITION
#   - SLURM_JOBID
#   - SLURM_JOB_START_TIME
#   - SLURM_JOB_END_TIME
#
# The script also requires the following environment variables:
#   - STANDARD_NODE_EXCLUDE_LIST_FILE: 
#         A file containing a comma-separated list of nodes to be excluded for the
#         'standard' partition. This file will be updated to include additionally
#         the current node if the current node is found to not have enough memory
#   - STANDARD_G_NODE_EXCLUDE_LIST_FILE: 
#         A file containing a comma-separated list of nodes to be excluded for the
#         'standard-g' partition. This file will be updated to include additionally
#         the current node if the current node is found to not have enough memory
#   - GLOBAL_DEPS_LOCK_FILE: A global lock file to atomize operations across different jobs
#
# The following are optional environment variables
#   - SYSTEM_MEMORY:
#       The amount of memory that one can afford to have (in KB) previously
#       allocated to the system. by default its 65GB.
#
# Dependencies:
#   The script depends on the following tools:
#     - free
#     - scontrol
#     - squeue
#     - sbatch
#     - awk
#     - grep
#     - cut
#     - date
#     - perl
#
# Note:
#   Make sure this script has the required executable permissions.
################################################################################

# Get script directory
SOURCE="${BASH_SOURCE[0]}"
SOURCE=$(readlink -f "$SOURCE")
SOURCE_DIR=$(dirname "$SOURCE")

# to get replace_jobids_in_dependency
source "$SOURCE_DIR/batcherutils.bash"

get_output_for_all_nodes() {
    srun --tasks-per-node 1 --ntasks $SLURM_JOB_NUM_NODES bash -c 'echo "$(hostname) $('"$1"')"' | sort -k1 | cut -f 2
}

CPUS_PER_TASK=$SLURM_CPUS_PER_TASK
NUM_TASKS_PER_NODE=$(echo "$SLURM_TASKS_PER_NODE" | grep -oP '^\d+')
IFS='' read -r -d '' total_cpus_command <<"EOF"
    TOTAL_SOCKETS_ON_NODE="$(srun --input=none --ntasks 1 lscpu | grep -oP '^Socket\(s\): +?\K\d+')"
    TOTAL_CORES_PER_SOCKET_ON_NODE="$(srun --input=none --ntasks 1 lscpu | grep -oP '^Core\(s\) per socket: +?\K\d+')"
    TOTAL_CPUS_ON_NODE="$((TOTAL_SOCKETS_ON_NODE * TOTAL_CORES_PER_SOCKET_ON_NODE))"
    echo $TOTAL_CPUS_ON_NODE
EOF

TOTAL_CPUS_ON_ALL_NODES=$(get_output_for_all_nodes "$total_cpus_command")

NODES="$(get_output_for_all_nodes hostname)"
if [[ -z "$SYSTEM_MEMORY" ]]; then
    SYSTEM_MEMORY=68157440 # 70GB in KB
fi

IFS='' read -r -d '' total_memory_command <<"EOF"
    free -k | grep 'Mem:' | awk '{print $2}'
EOF

TOTAL_MEMORY_ON_ALL_NODES=$(get_output_for_all_nodes "$total_memory_command")
REQUIRED_MEM_ON_ALL_NODES=$(
    for tot_mem in ${TOTAL_MEMORY_ON_ALL_NODES}; do
        perl -e "print ''.(int(($CPUS_PER_TASK * $NUM_TASKS_PER_NODE / $TOTAL_CPUS_ON_NODE) * ($tot_mem - $SYSTEM_MEMORY)))"; echo
    done
)

IFS='' read -r -d '' available_memory_command <<"EOF"
    free -k | grep 'Mem:' | awk '{print $7}'
EOF
AVAILABLE_MEMORY_ON_ALL_NODES=$(get_output_for_all_nodes "$available_memory_command")


NODES_TO_EXCLUDE=()
while read node req_mem avail_mem; do
    if [[ $avail_mem -lt $req_mem ]]; then
        NODES_TO_EXCLUDE+=($node)
    fi
done < <(paste <(echo "$NODES") <(echo "$REQUIRED_MEM_ON_ALL_NODES") <(echo "$AVAILABLE_MEMORY_ON_ALL_NODES"))
unset node req_mem avail_mem
NODES_TO_EXCLUDE="$(IFS=','; echo "${NODES_TO_EXCLUDE[*]}")"

echo "CURRENT NODES"
echo "$NODES"
echo "CPUS_PER_TASK=$CPUS_PER_TASK NUM_TASKS=$NUM_TASKS TOTAL_CPUS_ON_NODE=$TOTAL_CPUS_ON_NODE"
echo "SYSTEM_MEMORY = $SYSTEM_MEMORY TOTAL_MEMORY=$TOTAL_MEMORY"
echo "REQUIRED_MEM = $REQUIRED_MEM"
echo "AVAILABLE_MEMORY_ON_ALL_NODES=$AVAILABLE_MEMORY"
echo "NODES_TO_EXCLUDE=$NODES_TO_EXCLUDE"

if [[ -n "$NODES_TO_EXCLUDE" ]]; then
    echo "Insufficient Memory on nodes $NODES_TO_EXCLUDE, restarting simulation"

    lock_timeout_seconds=50

    if [[ $SLURM_JOB_PARTITION == 'standard' ]]; then
        EXCLUDE_LIST_FILE_env=STANDARD_NODE_EXCLUDE_LIST_FILE
    elif [[ $SLURM_JOB_PARTITION == 'standard-g' ]]; then
        EXCLUDE_LIST_FILE_env=STANDARD_G_NODE_EXCLUDE_LIST_FILE
    elif [[ $SLURM_JOB_PARTITION == 'small' ]]; then
        EXCLUDE_LIST_FILE_env=SMALL_NODE_EXCLUDE_LIST_FILE
    elif [[ $SLURM_JOB_PARTITION == 'small-g' ]]; then
        EXCLUDE_LIST_FILE_env=SMALL_G_NODE_EXCLUDE_LIST_FILE
    fi &&
    declare -n EXCLUDE_LIST_FILE=$EXCLUDE_LIST_FILE_env &&
    [[ -n "$EXCLUDE_LIST_FILE" ]] || {
        echo "Could not find file to store exclude list, exiting without replacement process" >&2
        exit 1
    }

    if [[ -z "$GLOBAL_DEPS_LOCK_FILE" ]]; then
        echo "Could not find global lock file to coordinate Dependency replacement" >&2
        exit 1
    fi

    (
    if flock -w "${lock_timeout_seconds}" 9; then
        EXCLUDED_NODES=$(cat "$EXCLUDE_LIST_FILE")
        echo "PREVIOUSLY EXCLUDED_NODES = $EXCLUDED_NODES"
        if [[ -z $EXCLUDED_NODES ]]; then
            NEW_EXCLUDED_NODES=$NODES_TO_EXCLUDE
        else
            NEW_EXCLUDED_NODES="$EXCLUDED_NODES,$NODES_TO_EXCLUDE"
        fi

        echo "NEW EXCLUDED_NODES = $NEW_EXCLUDED_NODES"
        echo $NEW_EXCLUDED_NODES > "$EXCLUDE_LIST_FILE"
    else
        echo "Could not Acquire global lock to edit excluded files, terminating without launching replacement job" >&2
        exit 1
    fi
    ) 9>"$GLOBAL_DEPS_LOCK_FILE"

    # Needs to be read again as variable is previously set in subshell
    # THis is okay as echo is atomic when writing a single line
    NEW_EXCLUDED_NODES=$(cat $EXCLUDE_LIST_FILE)

    # Get the original script path
    SCRIPT_PATH=$(scontrol show job $SLURM_JOB_ID | grep -Po "Command=\K\S*" | head -n 1)
    TIME_LIMIT=$(squeue --noheader -j "$SLURM_JOB_ID" -o "%l")

    # Launch a new job with the updated excluded nodes
    # Launch a new job with the updated excluded nodes and identical parameters
                       # --output=rerun-%j.out \
                       # --error=rerun-%j.err \

    if [[ -n "$SLURM_GPUS_PER_TASK" ]]; then
        GPUS_PRE_TASK_OPTION=--gpus-per-task=$SLURM_GPUS_PER_TASK
    fi
    if [[ -n "$SLURM_MEM_PER_CPU" ]]; then
        MEM_PER_CPU_OPTION=--mem-per-cpu=$SLURM_MEM_PER_CPU
    fi

    rerun_index=$(echo "$SLURM_JOB_NAME" | grep -Po '_rerun_\K\d+$' || echo "0")
    job_name_without_rerun_suffix=$(echo "$SLURM_JOB_NAME" | grep -Po '.*(?=(_rerun_\d+)?$)')
    rerun_index=$(( rerun_index + 1 ))

    # Note that this job is launched with a dependency on the current job so that that job only begins once this is done
    sbatch_command=(sbatch -vv -p "$SLURM_JOB_PARTITION" --parsable --exclude=$NEW_EXCLUDED_NODES \
                       --dependency=afterany:$SLURM_JOB_ID
                       --job-name "${job_name_without_rerun_suffix}_rerun_${rerun_index}"
                       --output="$(scontrol show job $SLURM_JOB_ID | grep -oP 'StdOut=\K.*?(?=_rerun_\d+|$)')_rerun_%j" \
                       --error="$(scontrol show job $SLURM_JOB_ID | grep -oP 'StdErr=\K.*?(?=_rerun_\d+|$)')_rerun_%j" \
                       --mem=0 \
                       --cpus-per-task=$CPUS_PER_TASK \
                       $GPUS_PRE_TASK_OPTION \
                       $MEM_PER_CPU_OPTION \
                       --ntasks=$NUM_TASKS \
                       --time=$TIME_LIMIT \
                       $SCRIPT_PATH "$@")
    NEW_JOB_ID=$("${sbatch_command[@]}")

    echo "Launching new job $NEW_JOB_ID instead of $SLURM_JOB_ID, with command "
    echo "${sbatch_command[@]}"

    # Update dependencies in a locked manner
    (
      if flock -w "${lock_timeout_seconds}" 9; then
        echo "Lock acquired: $GLOBAL_DEPS_LOCK_FILE, performing Dependency replacement for job $SLURM_JOB_ID"

        # Get all dependecies
        DEP_JOBID_DEPS=$(squeue -u "$USER" -h -t PD --noheader -O 'JobID:11,Dependency:2000' | perl -npe 's/\([^)]+\) *//g')
        # Filter those containing current job as dependency
        DEP_JOBID_DEPS=$(echo "$DEP_JOBID_DEPS" | grep -P '(?<!^)\b'"$SLURM_JOB_ID"'\b')
        # Extract JOBIDs and JOBDEPs
        DEP_JOBIDs=$(echo "$DEP_JOBID_DEPS" | tr -s ' ' | cut -d' ' -f1)
        DEP_JOBDEPs=$(echo "$DEP_JOBID_DEPS" | tr -s ' ' | cut -d' ' -f2)

        echo "DEP_JOBIDs:"
        echo "$DEP_JOBIDs"
        echo
        echo "DEP_JOBDEPs:"
        echo "$DEP_JOBDEPs"

        if [[ -n "$DEP_JOBIDs" ]]; then
            declare -A old_id_to_new_id_map=([$SLURM_JOB_ID]=$NEW_JOB_ID)
            readarray -t DEP_JOBIDs_ARR <<< "$DEP_JOBIDs"
            readarray -t DEP_JOBDEPs_ARR <<< "$DEP_JOBDEPs"
            for i in "${!DEP_JOBIDs_ARR[@]}"; do
                JOB_ID="${DEP_JOBIDs_ARR[$i]}"                                          &&
                JOB_DEP="${DEP_JOBDEPs_ARR[$i]}"                                        &&
                NEW_DEP=$(replace_jobids_in_dependency old_id_to_new_id_map "$JOB_DEP") &&
                echo "Updating Dependency of job $JOB_ID from $JOB_DEP to $NEW_DEP "    &&
                scontrol update JobId=$JOB_ID Dependency="$NEW_DEP"
            done
        fi

      else
        scancel $NEW_JOB_ID
      fi
      # Your command or script to execute with the file locked goes here
    ) 9>"$GLOBAL_DEPS_LOCK_FILE"


    # Exit the current job
    exit 
else
  exit 0
fi
