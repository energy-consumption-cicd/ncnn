#!/usr/bin/env bash

set -euo pipefail

RUN_NUM="${1:?run number required (e.g. 1)}"
PROJECT_NAME="ncnn"
IMAGE_NAME="ncnn-medicao"
MEDICAO_DIR="$HOME/experimentos/medicao/repositorios/ncnn"
RESULTS_DIR="$HOME/experimentos/medicao/resultados/ncnn/runs"
RAPL_BASE="/sys/class/powercap/intel-rapl"
# Idle baseline measured before each run; its per-second rate is subtracted
# from every stage so reported energy reflects workload above idle.
BASELINE_DURATION=120
TIME_FILE="/tmp/ncnn_time_$$.txt"
CSV_FILE="$RESULTS_DIR/run_$(printf '%02d' "$RUN_NUM").csv"

BUILD_VOL="ncnn-builds-$$"

STAGES=(
  build_sse2 test_sse2
  build_shared
  build_avx2 test_avx2
  build_avx  test_avx
  build_avx1_2 test_avx1_2
  build_noint8 test_noint8
)

mkdir -p "$RESULTS_DIR"

if [ ! -d "$RAPL_BASE" ]; then
  echo "RAPL not available at $RAPL_BASE" >&2
  exit 1
fi

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "Docker image '$IMAGE_NAME' not found." >&2
  echo "  Build it first: docker build -t $IMAGE_NAME -f $MEDICAO_DIR/Dockerfile <fonte-ncnn>" >&2
  exit 1
fi

docker volume rm "$BUILD_VOL" &>/dev/null || true
docker volume create "$BUILD_VOL" >/dev/null
cleanup() {
  docker volume rm "$BUILD_VOL" &>/dev/null || true
  rm -f "$TIME_FILE"
}
trap cleanup EXIT

read_rapl() {
  local domain_name="$1"
  local value=0
  for dir in "$RAPL_BASE"/*/; do
    local name_file="$dir/name"
    [ -f "$name_file" ] || continue
    local name
    name=$(cat "$name_file")
    if [[ "$name" == "package-0" && "$domain_name" == "pkg" ]] || \
       [[ "$name" == "core"      && "$domain_name" == "cores" ]] || \
       [[ "$name" == "uncore"    && "$domain_name" == "gpu" ]] || \
       [[ "$name" == "dram"      && "$domain_name" == "ram" ]]; then
      local energy_file="$dir/energy_uj"
      [ -f "$energy_file" ] && value=$(cat "$energy_file") && break
    fi
    for subdir in "$dir"*/; do
      local sub_name_file="$subdir/name"
      [ -f "$sub_name_file" ] || continue
      local sub_name
      sub_name=$(cat "$sub_name_file")
      if [[ "$sub_name" == "core"   && "$domain_name" == "cores" ]] || \
         [[ "$sub_name" == "uncore" && "$domain_name" == "gpu" ]] || \
         [[ "$sub_name" == "dram"   && "$domain_name" == "ram" ]]; then
        local sub_energy="$subdir/energy_uj"
        [ -f "$sub_energy" ] && value=$(cat "$sub_energy") && break 2
      fi
    done
  done
  echo "$value"
}

read_rapl_max() {
  local domain_name="$1"
  local value=0
  for dir in "$RAPL_BASE"/*/; do
    local name_file="$dir/name"
    [ -f "$name_file" ] || continue
    local name
    name=$(cat "$name_file")
    if [[ "$name" == "package-0" && "$domain_name" == "pkg" ]]; then
      local max_file="$dir/max_energy_range_uj"
      [ -f "$max_file" ] && value=$(cat "$max_file") && break
    fi
    for subdir in "$dir"*/; do
      local sub_name_file="$subdir/name"
      [ -f "$sub_name_file" ] || continue
      local sub_name
      sub_name=$(cat "$sub_name_file")
      if [[ "$sub_name" == "core"   && "$domain_name" == "cores" ]] || \
         [[ "$sub_name" == "uncore" && "$domain_name" == "gpu" ]] || \
         [[ "$sub_name" == "dram"   && "$domain_name" == "ram" ]]; then
        local sub_max="$subdir/max_energy_range_uj"
        [ -f "$sub_max" ] && value=$(cat "$sub_max") && break 2
      fi
    done
  done
  [ "$value" -eq 0 ] && value=999999999999
  echo "$value"
}

# RAPL counters wrap at max_energy_range_uj; deltas are overflow-corrected.
delta_uj() {
  local ini="$1" fin="$2" max="$3"
  if [ "$fin" -ge "$ini" ]; then
    echo $(( fin - ini ))
  else
    echo $(( max - ini + fin ))
  fi
}

echo ""
echo ""
echo " Run $RUN_NUM - $PROJECT_NAME"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Baseline rest (${BASELINE_DURATION}s)..."

b_pkg_ini=$(read_rapl pkg)
b_cores_ini=$(read_rapl cores)
b_gpu_ini=$(read_rapl gpu)
b_ram_ini=$(read_rapl ram)

sleep "$BASELINE_DURATION"

b_pkg_fin=$(read_rapl pkg)
b_cores_fin=$(read_rapl cores)
b_gpu_fin=$(read_rapl gpu)
b_ram_fin=$(read_rapl ram)

max_pkg=$(read_rapl_max pkg)
max_cores=$(read_rapl_max cores)
max_gpu=$(read_rapl_max gpu)
max_ram=$(read_rapl_max ram)

b_delta_pkg=$(delta_uj "$b_pkg_ini" "$b_pkg_fin" "$max_pkg")
b_delta_cores=$(delta_uj "$b_cores_ini" "$b_cores_fin" "$max_cores")
b_delta_gpu=$(delta_uj "$b_gpu_ini" "$b_gpu_fin" "$max_gpu")
b_delta_ram=$(delta_uj "$b_ram_ini" "$b_ram_fin" "$max_ram")

taxa_pkg=$(awk  "BEGIN {printf \"%.6f\", $b_delta_pkg  / $BASELINE_DURATION}")
taxa_cores=$(awk "BEGIN {printf \"%.6f\", $b_delta_cores / $BASELINE_DURATION}")
taxa_gpu=$(awk  "BEGIN {printf \"%.6f\", $b_delta_gpu  / $BASELINE_DURATION}")
taxa_ram=$(awk  "BEGIN {printf \"%.6f\", $b_delta_ram  / $BASELINE_DURATION}")

echo "Baseline rate:"
echo "   pkg:   $(awk "BEGIN {printf \"%.2f\", $taxa_pkg / 1e6}") W"
echo "   cores: $(awk "BEGIN {printf \"%.2f\", $taxa_cores / 1e6}") W"
echo "   ram:   $(awk "BEGIN {printf \"%.2f\", $taxa_ram / 1e6}") W"

echo "run,stage,energy_pkg_j,energy_cores_j,energy_gpu_j,energy_ram_j,wall_time_s,user_time_s,sys_time_s,energy_ram_liquid_raw_j,wall_time_container_s" \
  > "$CSV_FILE"

tot_pkg=0; tot_cores=0; tot_gpu=0; tot_ram=0; tot_ram_raw=0; tot_wall=0; tot_user=0; tot_sys=0; tot_wallc=0
b_pkg=0;  b_cores=0;  b_gpu=0;  b_ram=0;  b_ram_raw=0;  b_wall=0;  b_user=0;  b_sys=0;  b_wallc=0
t_pkg=0;  t_cores=0;  t_gpu=0;  t_ram=0;  t_ram_raw=0;  t_wall=0;  t_user=0;  t_sys=0;  t_wallc=0

measure_stage() {
  local stage="$1"
  echo ""
  echo " Step: $stage - $(date '+%H:%M:%S')"

  local timing_dir
  timing_dir=$(mktemp -d)

  local ini_pkg ini_cores ini_gpu ini_ram
  ini_pkg=$(read_rapl pkg)
  ini_cores=$(read_rapl cores)
  ini_gpu=$(read_rapl gpu)
  ini_ram=$(read_rapl ram)

  # --network none: all inputs are pre-baked into the image; measured energy
  # must not include network traffic (construct definition).
  # fd3 preserves the workload stderr while `time` captures wall/user/sys inside
  # the container, so child CPU time is attributed to the stage.
  /usr/bin/time -f "%e" -o "$TIME_FILE" \
    docker run --rm --privileged --network none \
      -v "$MEDICAO_DIR:/medicao:ro" \
      -v "$BUILD_VOL:/builds" \
      -v "$timing_dir:/timing" \
      -e "STAGE=$stage" \
      "$IMAGE_NAME" \
      bash -c 'exec 3>&2; TIMEFORMAT="%R %U %S"; { time bash /medicao/commands.sh "$STAGE" 2>&3; } 2>/timing/time.txt'

  local fin_pkg fin_cores fin_gpu fin_ram
  fin_pkg=$(read_rapl pkg)
  fin_cores=$(read_rapl cores)
  fin_gpu=$(read_rapl gpu)
  fin_ram=$(read_rapl ram)

  local wall wall_container_t user_t sys_t
  wall=$(cat "$TIME_FILE")
  if [ -f "$timing_dir/time.txt" ]; then
    read -r wall_container_t user_t sys_t < "$timing_dir/time.txt"
  else
    wall_container_t="0.000"; user_t="0.000"; sys_t="0.000"
  fi
  rm -rf "$timing_dir"

  local d_pkg d_cores d_gpu d_ram
  d_pkg=$(delta_uj   "$ini_pkg"   "$fin_pkg"   "$max_pkg")
  d_cores=$(delta_uj "$ini_cores" "$fin_cores" "$max_cores")
  d_gpu=$(delta_uj   "$ini_gpu"   "$fin_gpu"   "$max_gpu")
  d_ram=$(delta_uj   "$ini_ram"   "$fin_ram"   "$max_ram")

  local j_pkg j_cores j_gpu j_ram j_ram_raw
  j_pkg=$(awk   "BEGIN {v=($d_pkg   - $taxa_pkg   * $wall) / 1e6; printf \"%.6f\", (v>0?v:0)}")
  j_cores=$(awk "BEGIN {v=($d_cores - $taxa_cores * $wall) / 1e6; printf \"%.6f\", (v>0?v:0)}")
  j_gpu=$(awk   "BEGIN {v=($d_gpu   - $taxa_gpu   * $wall) / 1e6; printf \"%.6f\", (v>0?v:0)}")
  j_ram=$(awk   "BEGIN {v=($d_ram   - $taxa_ram   * $wall) / 1e6; printf \"%.6f\", (v>0?v:0)}")
  j_ram_raw=$(awk "BEGIN {printf \"%.6f\", ($d_ram - $taxa_ram * $wall) / 1e6}")

  echo "$RUN_NUM,$stage,$j_pkg,$j_cores,$j_gpu,$j_ram,$wall,$user_t,$sys_t,$j_ram_raw,$wall_container_t" >> "$CSV_FILE"

  tot_pkg=$(awk "BEGIN{printf\"%.6f\",$tot_pkg+$j_pkg}");       tot_cores=$(awk "BEGIN{printf\"%.6f\",$tot_cores+$j_cores}")
  tot_gpu=$(awk "BEGIN{printf\"%.6f\",$tot_gpu+$j_gpu}");       tot_ram=$(awk "BEGIN{printf\"%.6f\",$tot_ram+$j_ram}")
  tot_ram_raw=$(awk "BEGIN{printf\"%.6f\",$tot_ram_raw+$j_ram_raw}")
  tot_wall=$(awk "BEGIN{printf\"%.3f\",$tot_wall+$wall}");      tot_user=$(awk "BEGIN{printf\"%.3f\",$tot_user+$user_t}")
  tot_sys=$(awk "BEGIN{printf\"%.3f\",$tot_sys+$sys_t}");       tot_wallc=$(awk "BEGIN{printf\"%.3f\",$tot_wallc+$wall_container_t}")

  if [[ "$stage" == build_* ]]; then
    b_pkg=$(awk "BEGIN{printf\"%.6f\",$b_pkg+$j_pkg}");         b_cores=$(awk "BEGIN{printf\"%.6f\",$b_cores+$j_cores}")
    b_gpu=$(awk "BEGIN{printf\"%.6f\",$b_gpu+$j_gpu}");         b_ram=$(awk "BEGIN{printf\"%.6f\",$b_ram+$j_ram}")
    b_ram_raw=$(awk "BEGIN{printf\"%.6f\",$b_ram_raw+$j_ram_raw}")
    b_wall=$(awk "BEGIN{printf\"%.3f\",$b_wall+$wall}");        b_user=$(awk "BEGIN{printf\"%.3f\",$b_user+$user_t}")
    b_sys=$(awk "BEGIN{printf\"%.3f\",$b_sys+$sys_t}");         b_wallc=$(awk "BEGIN{printf\"%.3f\",$b_wallc+$wall_container_t}")
  elif [[ "$stage" == test_* ]]; then
    t_pkg=$(awk "BEGIN{printf\"%.6f\",$t_pkg+$j_pkg}");         t_cores=$(awk "BEGIN{printf\"%.6f\",$t_cores+$j_cores}")
    t_gpu=$(awk "BEGIN{printf\"%.6f\",$t_gpu+$j_gpu}");         t_ram=$(awk "BEGIN{printf\"%.6f\",$t_ram+$j_ram}")
    t_ram_raw=$(awk "BEGIN{printf\"%.6f\",$t_ram_raw+$j_ram_raw}")
    t_wall=$(awk "BEGIN{printf\"%.3f\",$t_wall+$wall}");        t_user=$(awk "BEGIN{printf\"%.3f\",$t_user+$user_t}")
    t_sys=$(awk "BEGIN{printf\"%.3f\",$t_sys+$sys_t}");         t_wallc=$(awk "BEGIN{printf\"%.3f\",$t_wallc+$wall_container_t}")
  fi

  echo "    pkg: ${j_pkg}J | cores: ${j_cores}J | ram: ${j_ram}J | wall: ${wall}s"
}

for st in "${STAGES[@]}"; do
  measure_stage "$st"
done

echo "$RUN_NUM,build,$b_pkg,$b_cores,$b_gpu,$b_ram,$b_wall,$b_user,$b_sys,$b_ram_raw,$b_wallc"       >> "$CSV_FILE"
echo "$RUN_NUM,test,$t_pkg,$t_cores,$t_gpu,$t_ram,$t_wall,$t_user,$t_sys,$t_ram_raw,$t_wallc"        >> "$CSV_FILE"
echo "$RUN_NUM,total,$tot_pkg,$tot_cores,$tot_gpu,$tot_ram,$tot_wall,$tot_user,$tot_sys,$tot_ram_raw,$tot_wallc" >> "$CSV_FILE"

echo ""
echo ""
echo "Run $RUN_NUM finished - $(date '+%H:%M:%S')"
echo " CSV: $CSV_FILE"
echo " Total: pkg=${tot_pkg}J | wall=${tot_wall}s"
echo ""
echo ""

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF

## Run $RUN_NUM - $PROJECT_NAME

| Stage | pkg (J) | cores (J) | gpu (J) | ram (J) | wall (s) |
|-------|---------|-----------|---------|---------|----------|
$(grep "^$RUN_NUM," "$CSV_FILE" | awk -F',' '{printf "| %s | %s | %s | %s | %s | %s |\n", $2,$3,$4,$5,$6,$7}')
EOF
fi
