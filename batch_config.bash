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
# Batch Configuration for the batch processing script
#
# This configuration file sets SBATCH options and batch sizes for different
# types of jobs to be processed by the batch processing script.
#
# Arrays to be defined in this file:
#   1. script_ordered_list: An array of script names in the order they should be processed.
#   2. SBATCH_opts: An associative array mapping script names to SBATCH options.
#   3. BATCHSIZE: An associative array mapping script names to batch sizes (number of jobs to run in parallel).
#
# script_ordered_list example:
#
#     script_ordered_list=(
#         ScriptName1
#         ScriptName2
#         ScriptName3
#     )
#
# SBATCH_opts example:
#
#     SBATCH_opts=(
#         ["ScriptName1"]="-p partition1 --cpus-per-task 4 --mem=0 -t 01:00:00"
#         ["ScriptName2"]="-p partition2 --cpus-per-task 8 --mem=0 -t 02:00:00"
#         ["ScriptName3"]="-p partition3 --cpus-per-task 16 --mem=0 -t 03:00:00"
#     )
#
# BATCHSIZE example:
# 
#     BATCHSIZE=(
#         ["ScriptName1"]="4"
#         ["ScriptName2"]="8"
#         ["ScriptName3"]="16"
#     )
#
# Replace the example values above with the appropriate values for your specific use case.
################################################################################

# This is a sample configuration based on the LUMI supercomputer (feel free to change this as fit)
# script_ordered_list example:
script_ordered_list=(
	DataGeneration
	PreTrainining
	MainTrainingLoop
	PostTraining
	Validation
)

SBATCH_opts=(
    ["DataGeneration"]="-p standard -x nid001069,nid001070 --cpus-per-task 32 --mem=0 -t 01:00:00"
    ["PreTrainining"]="-p standard-g --cpus-per-task 7 --gpus-per-task 1 --mem=0 -t 01:00:00"
    ["MainTrainingLoop"]="-p standard -x nid001069,nid001070 --cpus-per-task 16 --mem=0 -t 01:30:00"
    ["PostTraining"]="-p standard -x nid001069,nid001070 --cpus-per-task 32 --mem=0 -t 03:30:00"
    ["Validation"]="-p standard -x nid001069,nid001070 --cpus-per-task 8 --mem=0 -t 00:45:00"
)

BATCHSIZE=(
    ["DataGeneration"]="4"
    ["PreTrainining"]="8"
    ["MainTrainingLoop"]="8"
    ["PostTraining"]="4"
    ["Validation"]="15"
)
