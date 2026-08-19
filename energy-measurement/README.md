# Energy measurement instrumentation

## Purpose

This directory is not part of the upstream ncnn repository. It was added to
measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. Verify with:

```bash
git remote add upstream https://github.com/Tencent/ncnn.git
git fetch upstream
git diff --name-only upstream/master...HEAD
```

## What is measured

Energy is read from the Intel RAPL counters under
`/sys/class/powercap/intel-rapl`, for four domains: package (`pkg`), cores,
uncore (reported as `gpu`, structurally zero on this bench) and DRAM (`ram`).
Counter deltas are overflow-corrected against `max_energy_range_uj`, read from
sysfs at run time rather than hardcoded.

Each run measures a 120 s idle baseline first and derives a per-second rate per
domain. Reported energy per stage is

```
net = max(raw_delta - baseline_rate * wall_time_s, 0)
```

The clamp at zero prevents a negative DRAM figure on light memory workloads;
the unclamped DRAM value is kept as the diagnostic column
`energy_ram_liquid_raw_j`.

`wall_time_s` covers the whole `docker run --rm` lifecycle, including container
setup and teardown, because the RAPL reading window covers the same interval.
`wall_time_container_s` is measured inside the container; the difference
isolates container overhead, which in this project is larger than in the others
because of the shared build volume described below.

Per-stage CPU time is captured inside the container: file descriptor 3
preserves the workload's stderr while `time` writes to `/timing`, so the CPU
time of child processes is attributed to the stage.

## How to run

```bash
docker build -t ncnn-medicao -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml -f campaign=full         # warm-up + 10 runs
```

## Stages

ncnn is an inference-only C++ project: the pipeline has no training stage. The
eleven steps of the upstream job are measured **individually, in the original
order**, and then aggregated into `build` and `test` rows.

| measured step | corresponds to |
|---|---|
| `build_sse2`, `test_sse2` | upstream `build-sse2`, `test-sse2` |
| `build_shared` | upstream `build-shared` (no ctest upstream either) |
| `build_avx2`, `test_avx2` | upstream `build-avx2`, `test-avx2` |
| `build_avx`, `test_avx` | upstream `build-avx`, `test-avx` |
| `build_avx1_2`, `test_avx1_2` | upstream `build-avx1-2`, `test-avx1-2` |
| `build_noint8`, `test_noint8` | upstream `build-noint8`, `test-noint8` |

The `build` and `test` rows are the aggregates that make this project
comparable with the others; the per-step rows are the ISA sub-analysis.
`cmake --build -j $(nproc)` and `ctest -j $(nproc)` are inherited verbatim.

Reference cell: `linux-x64-cpu-gcc.yml`, job `linux-gcc`.

## Deviations from the upstream pipeline

- **apt dependencies pre-baked.** `libprotobuf-dev`, `protobuf-compiler` and
  `libopencv-dev` are installed at image build time instead of inside the
  measured window. RAPL has no network domain, so a live `apt-get` would
  inflate wall time without proportional energy.
- **`--network none`.** The measured containers have no network.
- **Pre-baked test model.** The model `test_squeezenet` expects is placed at the
  path the ctest resolves to, because the build tree is relocated to a shared
  volume (see below); without it the test would fail for a reason unrelated to
  the code under test.
- **Shared build volume.** The six build trees live in a Docker volume mounted
  at `/builds`, so each measured stage sees the state the previous one left.
  This is what makes step-level measurement possible, and it is also why this
  project's container teardown overhead is the largest in the study.
- **No memory limit.** This campaign predates the `--memory` convention adopted
  later; the flag is absent by generation, not by choice.

## Output schema

One CSV per run, one row per measured step, plus aggregated `build` and `test`
rows and a `total` row:

```
run, stage, energy_pkg_j, energy_cores_j, energy_gpu_j, energy_ram_j,
wall_time_s, user_time_s, sys_time_s, energy_ram_liquid_raw_j,
wall_time_container_s
```

The first nine columns are the official schema shared by every project in the
study; the last two are diagnostic. Exit codes are written to a sidecar
`exit_codes_run_NN.txt`.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none`, with the `/builds` volume
mounted.

Parallelism comes from `$(nproc)`, which resolves to 8 on this bench against 4
on a GitHub-hosted runner; the value is inherited from the upstream job and is
not overridden.
