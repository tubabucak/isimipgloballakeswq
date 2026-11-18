#!/bin/bash -l
# Step 3 for the Danish test (after hpc/run_denmark.sh), lownutr/highnutr x 4 models:
#   sbatch hpc/isimip_output_denmark.sh
# Uses example_climate/ (no ISIMIP_FORCING_DIR), so the files cover 1991-2000.
#SBATCH --job-name=ler-wq-isimip-dnk
#SBATCH --partition=zen4
#SBATCH --export=NONE
#SBATCH --array=0-7
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=4:00:00
#SBATCH --output=logs/isimip_output_dnk_%A_%a.out

# ~/env_lerwq.sh: R module, netCDF module (nccopy), R_LIBS_USER with LakeEnsemblR.WQ
source ~/env_lerwq.sh
echo "Node: $(hostname)  type: $VSC_ARCH_LOCAL  library: $R_LIBS_USER"
[ -e "$R_LIBS_USER/LakeEnsemblR.WQ" ] || { echo "No shared library for $VSC_ARCH_LOCAL"; exit 1; }

# 03_isimip_output.R reads logs named task_*.csv; the Danish logs are dnk_task_*.csv
log_dir=runs/obsclim/gswp3-era5/logs
for f in "$log_dir"/dnk_task_*.csv; do
  [ -e "$f" ] && cp -n "$f" "$log_dir/task_$(basename "$f")"
done

sets=(lownutr highnutr)
models=(GLM WET SELMAPROTBAS SIMSTRAT)
set=${sets[$((SLURM_ARRAY_TASK_ID / 4))]}
model=${models[$((SLURM_ARRAY_TASK_ID % 4))]}

Rscript scripts/03_isimip_output.R "$set" "$model"
