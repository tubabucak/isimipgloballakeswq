#!/bin/bash -l
# Step 2 for the 40 Danish lakes (test with example_climate/, 1991-2000):
# 4 array tasks of block_size = 10 lakes. From the project root:
#   mkdir -p logs
#   sbatch --array=1-4 hpc/run_denmark.sh
# Resubmit one task (lakes with metrics.rds are skipped):
#   sbatch --array=3 hpc/run_denmark.sh
# Then the ISIMIP files as usual (hpc/isimip_output.sh).
#SBATCH --job-name=ler-wq-dnk
#SBATCH --partition=zen4
#SBATCH --export=NONE
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=logs/run_denmark_%A_%a.out

source ~/env_lerwq.sh
echo "Node: $(hostname)  type: $VSC_ARCH_LOCAL  library: $R_LIBS_USER"
[ -e "$R_LIBS_USER/LakeEnsemblR.WQ" ] || { echo "No shared library for $VSC_ARCH_LOCAL"; exit 1; }

Rscript scripts/02_run_denmark.R
