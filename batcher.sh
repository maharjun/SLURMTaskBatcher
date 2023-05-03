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
# This script reads a YAML file containing a list of job entries and batches
# the jobs to be executed using the 'run_multiple.sh' script. The jobs are
# processed and submitted to an HPC cluster using the SLURM workload manager.
#
# The script also reads a batch configuration file ('batch_config.bash') to set
# SBATCH options and batch sizes for different types of jobs.
#
# Usage:
#   batcher.sh config_file command_list_file
#
# Arguments:
#   command_list_file: Path to a YAML file containing a list of job entries, each
#                      with the following keys:
#                        - PSEUDOJOBID : A unique integer identifier for the job entry.
#                        - SCRIPTNAME : A name for the current simulation.
#                        - COMMAND    : A command to run (executed using bash -c).
#                        - LOGPREFIX  : Path to the log file, suffixed by _OUT.txt and _ERR.txt.
#                        - DEPENDENCY : A SLURM-style dependency string, e.g., "afterok:16436".
#
# Prerequisites:
#   - Ensure that the script is executable (chmod +x batcher.sh) before running.
#   - Install yq (https://github.com/mikefarah/yq/#install) to parse YAML files.
#   - Prepare a 'batch_config.bash' file that sets SBATCH options and batch sizes
#     for different types of jobs.
#   - Make sure 'run_multiple.sh' is properly configured and executable.
#
# The config file should be a bash source file which should define the following arrays:
#   1. script_ordered_list: An array of script names in the order they should be dispatched.
#                           This order is important especially if there are any dependencies
#   2. SBATCH_opts: An associative array mapping script names to SBATCH options.
#   3. BATCHSIZE: An associative array mapping script names to batch sizes (number of jobs to run in parallel).
#
################################################################################

# Validate presence of yq yaml processor
which yq 1>/dev/null 2>&1 || echo "yq is not found in PATH, install yq from https://github.com/mikefarah/yq/#install"

# Get script directory
SOURCE="${BASH_SOURCE[0]}"
SOURCE=$(readlink -f "$SOURCE")
SOURCE_DIR=$(dirname "$SOURCE")

if [[ -z "$CLUSTER_TEMP" ]]; then
    echo "The environment variable CLUSTER_TEMP must be set to a shared directory to store temporary files" >&2
    exit 1
fi

# This helps exclude nodes that don't have sufficient memory
export STANDARD_NODE_EXCLUDE_LIST_FILE=$(mktemp $CLUSTER_TEMP/tmpnodeexcludelist.XXXX)
export STANDARD_G_NODE_EXCLUDE_LIST_FILE=$(mktemp $CLUSTER_TEMP/tmpnodeexcludelist.XXXX)
export SMALL_NODE_EXCLUDE_LIST_FILE=$(mktemp $CLUSTER_TEMP/tmpnodeexcludelist.XXXX)
export SMALL_G_NODE_EXCLUDE_LIST_FILE=$(mktemp $CLUSTER_TEMP/tmpnodeexcludelist.XXXX)
export GLOBAL_DEPS_LOCK_FILE=$(mktemp $CLUSTER_TEMP/globaldepslock.XXXX)

# Read command_list file as input
command_list="$1"

if [ -z "$command_list" ]; then
    echo "Please provide a command_list file as input" >&2
    exit 1
fi

# Define scriptnames and corresponding variables
declare -A SBATCH_opts
declare -a script_ordered_list
declare -A BATCHSIZE

source $SOURCE_DIR/batch_config.bash

if [[ -z "${!SBATCH_opts[@]}" ]]; then
    echo "It appears that SBATCH_opts has not been set in batcher.sh!!" >&2
    echo "Please configure this. See examples in code for documentation" >&2
    exit 1
fi
if [[ -z "${!BATCHSIZE[@]}" ]]; then
    echo "It appears that BATCHSIZE has not been set in batcher.sh!!" >&2
    echo "Please configure this. See examples in code for documentation" >&2
    exit 1
fi

declare -A pseudo_to_actual_jobid

source $SOURCE_DIR/batcherutils.bash

# create log directory
LOGDIR=ignored/logs/slurm_runs/generic
if [[ ! -d "$LOGDIR" ]]; then
    mkdir -p "$LOGDIR"
fi

# Read the command_list and process each scriptname
for scriptname in "${script_ordered_list[@]}"; do
    script_jobs=$(yq eval "map(select(.SCRIPTNAME == \"$scriptname\"))" "$command_list")

    num_jobs="$(yq eval "length" - <<<"$script_jobs")"
    batch_size="${BATCHSIZE[$scriptname]}"
    sbatch_opts="${SBATCH_opts[$scriptname]}"
    
    for ((i=0; i<$num_jobs; i+=$batch_size)); do
        batch=$(yq eval ".[$i:$((i+batch_size))]" - <<<"$script_jobs")
        curr_bszize=$(yq eval "length" - <<<"$batch")

        dependencies=()
        pseudo_jobids=""

        for j in $(seq 0 1 $((curr_bszize-1))); do
            # pseudo_id=$(echo "$jobline" | grep -oP '^PSEUDOJOBID: \K\d+')
            # dependency=$(echo "$jobline" | grep -oP 'DEPENDENCY: \K.*$')
            pseudo_id=$(yq eval ".[$j].PSEUDOJOBID" - <<<"$batch")
            dependency=$(yq eval ".[$j].DEPENDENCY" - <<<"$batch")
            actual_dependency=$(replace_jobids_in_dependency pseudo_to_actual_jobid "$dependency")

            # Only get unique dependencies
            if [[ ! " ${dependencies[*]} " =~ " ${actual_dependency} " ]]; then
                dependencies+=("$actual_dependency")
            fi

            if [ -n "$pseudo_jobids" ]; then
                pseudo_jobids+=" "
            fi
            pseudo_jobids+="$pseudo_id"
        done

        # concatenate with , so that job runs if all of the dependencies is satisfied
        # Note that this means that if any one simulation fails, it will affect all the simulations that depend on it
        # This could cascade but in a low failure scenario this is unlikely and we can simply relaunch the jobs if this happens
        dependencies=$(IFS=','; echo "${dependencies[*]}")

        # echo "dependency = $dependencies"

        # --error=/dev/null --output=/dev/null
        if [[ -n "$dependencies" ]]; then
        	dependency_opt="--dependency=$dependencies"
        else
        	dependency_opt=""
        fi

        actual_jobid=$(sbatch $sbatch_opts --job-name $scriptname \
                                           --kill-on-invalid-dep=yes --parsable \
                                           --ntasks $batch_size $dependency_opt \
                                           --output=$LOGDIR/$scriptname-%j_OUT.txt \
                                           --error=$LOGDIR/$scriptname-%j_ERR.txt \
                                           $SOURCE_DIR/run_multiple.sh "$command_list" $pseudo_jobids)

        echo "For script $scriptname : Launched JobID: $actual_jobid containing pseudo_jobids $pseudo_jobids"
        # Update mapping from pseudo jobids to actual jobid
        for pseudo_id in $pseudo_jobids; do
            pseudo_to_actual_jobid["$pseudo_id"]="$actual_jobid"
        done
    done
done