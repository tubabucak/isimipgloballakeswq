#!/bin/bash
# Step 2: one array task per block of block_size lakes (00_settings.R).
# 41449 lakes / 10 = 4145 tasks of ~15 h (full period; check with the pilot).
# Many clusters limit array indices (scontrol show config | grep MaxArraySize),
# so submit in chunks of 1000 with TASK_OFFSET, from the project root
# (create logs/ first):
#   mkdir -p logs
#   sbatch --array=1-1000%200                         hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=ALL,TASK_OFFSET=1000 hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=ALL,TASK_OFFSET=2000 hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=ALL,TASK_OFFSET=3000 hpc/run_lakes.sh
#   sbatch --array=1-145%200  --export=ALL,TASK_OFFSET=4000 hpc/run_lakes.sh
# Resubmit failed or timed-out tasks only (lakes with metrics.rds are skipped),
# e.g. tasks 17 and 1042:
#   sbatch --array=17 hpc/run_lakes.sh
#   sbatch --array=42 --export=ALL,TASK_OFFSET=1000 hpc/run_lakes.sh
#SBATCH --job-name=ler-wq-lakes
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=logs/run_lakes_%A_%a.out

module load R          # adjust to the cluster's module names

Rscript scripts/02_run_lakes.R
