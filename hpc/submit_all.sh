#!/bin/bash -l
# Submit the whole global workflow from the project root (login node):
#   bash hpc/submit_all.sh
# Step 1 (data/inflow_table.csv) must exist already. Step 2 is submitted in
# chunks of at most 1000 array tasks (MaxArraySize), at most MAX_RUNNING of
# each chunk at once; step 3 starts when all chunks have ended (afterany:
# failed lakes are left out of the ISIMIP files, see the task logs).
set -euo pipefail

MAX_RUNNING=${MAX_RUNNING:-200}
CHUNK=1000

[ -f data/inflow_table.csv ] || { echo "Run step 1 first: Rscript scripts/01_inflow_table.R"; exit 1; }
mkdir -p logs

# number of tasks = ceiling(lakes / block_size), block_size from 00_settings.R
block_size=$(grep -E '^block_size' scripts/00_settings.R | sed -E 's/^block_size *<- *([0-9]+).*/\1/')
n_lakes=$(( $(wc -l < data/inflow_table.csv) - 1 ))
n_tasks=$(( (n_lakes + block_size - 1) / block_size ))
echo "$n_lakes lakes, $block_size per task: $n_tasks tasks"

jobs=()
for (( offset = 0; offset < n_tasks; offset += CHUNK )); do
  n=$(( n_tasks - offset < CHUNK ? n_tasks - offset : CHUNK ))
  id=$(sbatch --parsable --array=1-${n}%${MAX_RUNNING} \
         --export=TASK_OFFSET=${offset} hpc/run_lakes.sh)
  echo "step 2: tasks $((offset + 1))-$((offset + n))  job $id"
  jobs+=("$id")
done

dep=$(IFS=:; echo "${jobs[*]}")
id=$(sbatch --parsable --dependency=afterany:${dep} hpc/isimip_output.sh)
echo "step 3: job $id (starts after ${dep//:/, })"
