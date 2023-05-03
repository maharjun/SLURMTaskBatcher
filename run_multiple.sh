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
# This script is designed to run a series of specified jobs in parallel on an
# HPC cluster using the SLURM workload manager, with appropriate resource
# allocation, and cleaning up temporary files after the jobs are done. The
# script also takes into account dependencies between jobs based on pseudo job
# IDs, which are translated into SLURM job dependencies.
#
# Usage:
#   sbatch run_multiple.sh command_filename pseudo_jobid1 [pseudo_jobid2 ...]
#
# Arguments:
#   command_filename: Path to a YAML file containing a list of job entries, each
#                     with the following keys:
#                       - PSEUDOJOBID : A unique integer identifier for the job entry.
#                       - SCRIPTNAME : A name for the current simulation (not used in this script).
#                       - COMMAND    : A command to run (executed using bash -c).
#                       - LOGPREFIX  : Path to the log file, suffixed by _OUT.txt and _ERR.txt.
#                       - DEPENDENCY : A SLURM-style dependency string, e.g., "afterok:16436".
#   pseudo_jobid1, pseudo_jobid2, ... : A list of integers representing the
#                                       PSEUDOJOBID(s) of the jobs to be run.
#
# Example job entry in YAML file:
#   - PSEUDOJOBID: 16437
#     SCRIPTNAME: ExampleSimulation
#     COMMAND: 'example_command --input input.txt --output output.txt'
#     LOGPREFIX: /path/to/logs/example_simulation
#     DEPENDENCY: afterok:16436
#
# Note: Ensure that the script is executable (chmod +x run_multiple.sh) before running.
#       Make sure you have yq (https://github.com/mikefarah/yq) installed to parse YAML files.
################################################################################

# Get script directory
# From https://stackoverflow.com/a/56991068/3140750
if [[ -n $SLURM_JOB_ID && -z "$SLURM_STEP_ID" ]] ; then
    # If called via sbatch the script is copied elsewhere so we need this
    # Note that if called via a job-step then the code isn't copied
    echo "IN HERE 1"
    SOURCE=$(scontrol show job $SLURM_JOB_ID | grep -Po "Command=\K\S*" | head -n 1)
else
    echo "IN HERE 2"
    SOURCE="${BASH_SOURCE[0]}"
fi
echo "SOURCE=$SOURCE"
SOURCE=$(readlink -f "$SOURCE")
SOURCE_DIR=$(dirname "$SOURCE")

# Function to delete leftover temporary garbage files
clean_tmp_devshm() {
    echo "Cleaning up /tmp and /dev/shm"
    srun --ntasks 1 --input=none bash -c 'rm -rf /tmp/* /dev/shm/*' 2>/dev/null
}

# Trap the TERM signal
trap 'clean_tmp_devshm; exit 1' TERM

# Clean temporary files
clean_tmp_devshm 

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 command_filename pseudo_jobid1 [pseudo_jobid2 ...]" >&2
  exit 1
fi

command_filename=$1
shift 1
pseudo_jobids=("$@")
num_pseudo_jobids=${#pseudo_jobids[@]}

if [ $num_pseudo_jobids -gt ${SLURM_NTASKS} ]; then
  echo "Error: Number of line numbers must be at most the number of slurm tasks (num_pseudo_jobids: $num_pseudo_jobids, SLURM_NTASKS: $SLURM_NTASKS)" >&2
  exit 1
fi

# Check if enough memory is available, else reallocate job and exit
$SOURCE_DIR/rerun_if_insuf_memory.sh "$command_filename" "$@" || {
  exit $?
}

for pseudo_jobid in "${pseudo_jobids[@]}"; do
  job_entry=$(yq eval "map(select(.PSEUDOJOBID == $pseudo_jobid)) | .[0]" "$command_filename")
  log_prefix=$(yq eval ".LOGPREFIX" - <<<"$job_entry")
  command=$(yq eval ".COMMAND" - <<<"$job_entry")

  echo "JOB_ENTRY"
  echo "$job_entry"
  echo "COMMAND"
  echo "$command"

  if [[ -n "$SLURM_CPUS_PER_TASK" ]]; then
      CPUS_PER_TASK_OPTION="--cpus-per-task=$SLURM_CPUS_PER_TASK"
  fi
  if [[ -n "$SLURM_GPUS_PER_TASK" ]]; then
      GPUS_PER_TASK_OPTION="--gpus-per-task=$SLURM_GPUS_PER_TASK"
  fi

  echo "CPUS_PER_TASK_OPTION=$CPUS_PER_TASK_OPTION"
  echo "GPUS_PER_TASK_OPTION=$GPUS_PER_TASK_OPTION"

  srun $CPUS_PER_TASK_OPTION $GPUS_PER_TASK_OPTION --ntasks 1 \
       --output=${log_prefix}_OUT.txt \
       --error=${log_prefix}_ERR.txt \
       bash -c "$command" &
done

any_success=0
while [ $num_pseudo_jobids -gt 0 ]; do
  wait -n
  exit_status=$?
  if [ $exit_status -eq 0 ]; then
    any_success=1
  fi
  num_pseudo_jobids=$((num_pseudo_jobids - 1))
done

clean_tmp_devshm

exit $((1 - any_success))

