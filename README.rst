Batch Processing with SLURM
===========================

This project provides a set of scripts to run multiple jobs in parallel using SLURM job scheduler. It allows for easy configuration and management of batch jobs and their dependencies using a YAML input file and a batch configuration file.

Requirements
------------

- SLURM (Simple Linux Utility for Resource Management)
- `yq` - A command-line YAML processor (https://github.com/mikefarah/yq/#install)

Overview
--------

The project consists of the following scripts:

1. `run_multiple.sh`: The main script responsible for running jobs in parallel.
2. `batcher.sh`: The script that reads the YAML input file and batches jobs using `run_multiple.sh`.
3. `batch_config.sh`: The configuration file for setting batch options and sizes for different types of jobs.
4. `batcherutils.bash`: Contains utility functions for job management.

Usage
-----

1. Prepare a YAML input file containing the job specifications. Each job should have the following information:

.. code-block:: yaml

   - PSEUDOJOBID: 16437
     SCRIPTNAME: Name for current simulation
     COMMAND: 'command to run (run using bash -c)'
     LOGPREFIX: <path_of_log_file> (suffixed by _OUT.txt and _ERR.txt)
     DEPENDENCY: afterok:16436

2. Create a `batch_config.sh` file to define the job types, SBATCH options, and batch sizes. Define three arrays in this file:

- `script_ordered_list`: An array of script names in the order they should be processed.
- `SBATCH_opts`: An associative array mapping script names to SBATCH options.
- `BATCHSIZE`: An associative array mapping script names to batch sizes (number of jobs to run in parallel).

Refer to the inline documentation in `batch_config.sh` for examples.

3. Execute the `batcher.sh` script, providing the path to the YAML input file as an argument:

.. code-block:: bash

   ./batcher.sh path/to/your/input.yaml

The script will read the job specifications from the YAML input file, create batches using the `batch_config.sh` configuration, and submit the jobs to the SLURM scheduler.

Example
-------

Let's say you have two types of jobs, JobTypeA and JobTypeB, with different SBATCH options and batch sizes. Your `batch_config.sh` should look like:

.. code-block:: bash

   script_ordered_list=(
       JobTypeA
       JobTypeB
   )

   SBATCH_opts=(
       ["JobTypeA"]="-p partition1 --cpus-per-task 4 --mem=0 -t 01:00:00"
       ["JobTypeB"]="-p partition2 --cpus-per-task 8 --mem=0 -t 02:00:00"
   )

   BATCHSIZE=(
       ["JobTypeA"]="4"
       ["JobTypeB"]="8"
   )

Your YAML input file should contain the job specifications:

.. code-block:: yaml

   - PSEUDOJOBID: 1001
     SCRIPTNAME: JobTypeA
     COMMAND: echo 'Running JobTypeA - 1001'
     LOGPREFIX: logs/job_1001
     DEPENDENCY: afterok:1000

   - PSEUDOJOBID: 1002
     SCRIPTNAME: JobTypeB
     COMMAND: echo 'Running JobTypeB - 1002'
     LOGPREFIX: logs/job_1002
     DEPENDENCY: afterok:1001

Run the `batcher.sh` script:

.. code-block:: bash

   ./batcher.sh path/to/your/input.yaml


Adding Jobs Using yq
---------------------

A sample bash script that creates two jobs, with the second job depending on the first one, using `yq`. Here we assume that $STB_PATH contains the path to the directory containing the SLURMTaskBatcher scripts:

.. code-block:: bash

   #!/bin/bash

   # Create an empty YAML file
   echo "[]" > job_list.yaml

   # Source the utility scripts
   . $STB_PATH/batcherutils.sh

   # Set variables for the first job
   pseudo_job_id_1=$(inc_pseudo_job_id)
   option1_value_1="value1"
   option2_value_1="value2"
   previous_pseudo_job_id=""

   # Add the first job to the YAML file
   yq -i ". += {\"PSEUDOJOBID\": $pseudo_job_id_1}" job_list.yaml &&
   yq -i ".[-1] += {\"SCRIPTNAME\": \"JobScriptName1\"}" job_list.yaml &&
   yq -i ".[-1] += {\"COMMAND\": \"job_script_command.sh --first-option '$option1_value_1' --second-option '$option2_value_1'\"}" job_list.yaml &&
   yq -i ".[-1] += {\"LOGPREFIX\": \"$LOGDIR/JobScriptName1-%J-${option2_value_1}-${option1_value_1}\"}" job_list.yaml &&
   yq -i ".[-1] += {\"DEPENDENCY\": \"afterok:$previous_pseudo_job_id\"}" job_list.yaml || {
       echo "Error writing yaml file job_list.yaml" >&2
       exit 1
   }

   # Set variables for the second job
   pseudo_job_id_1=$(inc_pseudo_job_id)
   option1_value_2="value3"
   option2_value_2="value4"
   previous_pseudo_job_id=$pseudo_job_id_1

   # Add the second job to the YAML file, depending on the first job
   yq -i ". += {\"PSEUDOJOBID\": $pseudo_job_id_2}" job_list.yaml &&
   yq -i ".[-1] += {\"SCRIPTNAME\": \"JobScriptName2\"}" job_list.yaml &&
   yq -i ".[-1] += {\"COMMAND\": \"job_script_command.sh --first-option '$option1_value_2' --second-option '$option2_value_2'\"}" job_list.yaml &&
   yq -i ".[-1] += {\"LOGPREFIX\": \"$LOGDIR/JobScriptName2-%J-${option2_value_2}-${option1_value_2}\"}" job_list.yaml &&
   yq -i ".[-1] += {\"DEPENDENCY\": \"afterok:$previous_pseudo_job_id\"}" job_list.yaml || {
       echo "Error writing yaml file job_list.yaml" >&2
       exit 1
   }

   # Display the contents of the YAML file
   cat job_list.yaml

This script will create a `job_list.yaml` file containing two job specifications, where the second job depends on the completion of the first job. After creating the `job_list.yaml` file, you can run the `batcher.sh` script to submit the jobs as described in the previous sections.