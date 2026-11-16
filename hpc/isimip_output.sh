#!/bin/bash -l
# Step 3: one task per set x model (3 x 4 = 12), after all of step 2 has
# finished, e.g.:  sbatch --dependency=afterok:<step 2 job id> hpc/isimip_output.sh
#SBATCH --job-name=ler-wq-isimip
#SBATCH --partition=zen4
#SBATCH --export=NONE
#SBATCH --array=0-11
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=48:00:00
#SBATCH --output=logs/isimip_output_%A_%a.out

source "$VSC_DATA_VO/LERWQ/new_Tuba/env_tuba.sh"
module load netCDF/4.9.3-gompi-2025a    # nccopy, to convert the files to NETCDF4_CLASSIC
echo "Node: $(hostname)  type: $VSC_ARCH_LOCAL  library: $R_LIBS_USER"
[ -e "$R_LIBS_USER/LakeEnsemblR.WQ" ] || { echo "No shared library for $VSC_ARCH_LOCAL"; exit 1; }

sets=(lownutr highnutr default)
models=(GLM WET SELMAPROTBAS SIMSTRAT)
set=${sets[$((SLURM_ARRAY_TASK_ID / 4))]}
model=${models[$((SLURM_ARRAY_TASK_ID % 4))]}

Rscript scripts/03_isimip_output.R "$set" "$model"