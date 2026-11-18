#!/bin/bash -l
# Step 2: one array task per block of block_size lakes (00_settings.R).
# 41449 lakes / 10 = 4145 tasks of ~15 h (full period; check with the pilot).
# Many clusters limit array indices (scontrol show config | grep MaxArraySize),
# so submit in chunks of 1000 with TASK_OFFSET, from the project root
# (create logs/ first):
#   mkdir -p logs
#   sbatch --array=1-1000%200                         hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=TASK_OFFSET=1000 hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=TASK_OFFSET=2000 hpc/run_lakes.sh
#   sbatch --array=1-1000%200 --export=TASK_OFFSET=3000 hpc/run_lakes.sh
#   sbatch --array=1-145%200  --export=TASK_OFFSET=4000 hpc/run_lakes.sh
# Resubmit failed or timed-out tasks only (lakes with metrics.rds are skipped),
# e.g. tasks 17 and 1042:
#   sbatch --array=17 hpc/run_lakes.sh
#   sbatch --array=42 --export=TASK_OFFSET=1000 hpc/run_lakes.sh
#SBATCH --job-name=ler-wq-lakes
#SBATCH --partition=zen4
#SBATCH --export=NONE
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=logs/run_lakes_%A_%a.out

source ~/env_lerwq.sh
echo "Node: $(hostname)  type: $VSC_ARCH_LOCAL  library: $R_LIBS_USER"
[ -e "$R_LIBS_USER/LakeEnsemblR.WQ" ] || { echo "No shared library for $VSC_ARCH_LOCAL"; exit 1; }
export ISIMIP_FORCING_DIR=$VSC_DATA_VO/data/dataset/ISIMIP/ISIMIP4a/InputData/climate/atmosphere/obsclim/global/daily/historical/GSWP3-ERA5
Rscript scripts/02_run_lakes.R