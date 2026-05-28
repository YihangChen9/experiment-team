# Qwen Inference Receipt

This receipt documents a small cached-model inference experiment on the remote server using
`/mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct`.

It covers both execution modes:

- `run_local: true`: direct execution in the assigned remote workspace and host conda env.
- `run_local: false`: SkyPilot SSH container execution.

The tested query was:

```text
What is active inference?
```

## What We Learned

- Always check budget/server setup first. The setup endpoint confirmed the remote host had H100 GPUs, an `r3l` conda env, and a cached Qwen model.
- Push only the small inference workspace to the assigned remote workspace, for example `qwen_inference/`.
- In `run_local: true`, the host policy's `CUDA_VISIBLE_DEVICES=2` was correct. PyTorch saw CUDA and used the selected H100.
- In the SkyPilot container path, the allocated host GPU appeared inside the container as device `0`. The inherited `CUDA_VISIBLE_DEVICES=2` made PyTorch report `cuda_available: False`. Setting `CUDA_VISIBLE_DEVICES=0` inside the container fixed it.
- Host model paths are not automatically visible inside the SkyPilot container. Mount `/mnt/data0` with a Kubernetes `hostPath` volume when using `/mnt/data0/...` model paths.
- The container image had Torch but did not initially have `transformers` or `accelerate`; install or bake them into the image.

## Files Used

The receipt assumes these files exist under:

```text
$SKILL_DIR/assets/qwen_inference/
```

- `qwen_inference_test.py`
- `qwen_inference_run_local.conf.json`
- `qwen_inference_run_local.yaml`
- `qwen_inference_skypilot_container.conf.json`
- `qwen_inference_runtime_docker.yaml`
- `cuda_visible_test.py`
- `cuda_visible_runtime_docker.yaml`

## Inference Script

The core script loads the tokenizer/model from the local model path, uses CUDA if PyTorch can see it,
generates a short answer, and prints a clear summary block for `log_tail`.

Key behavior:

```python
MODEL_PATH = "/mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct"
QUERY = "What is active inference?"

tokenizer = AutoTokenizer.from_pretrained(
    MODEL_PATH,
    trust_remote_code=True,
    local_files_only=True,
)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    device_map="cuda:0" if torch.cuda.is_available() else "cpu",
    trust_remote_code=True,
    local_files_only=True,
)
```

The script should print at least:

```text
=== QWEN INFERENCE TEST START ===
model_path: /mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct
CUDA_VISIBLE_DEVICES: ...
cuda_available: ...
load_seconds: ...
=== QWEN INFERENCE TEST SUMMARY ===
generation_seconds: ...
answer: ...
=== QWEN INFERENCE TEST END ===
```

## Common Setup

Load credentials without printing the session key:

```bash
export SKILL_DIR="/absolute/path/to/default_skills/experiment-infra"
export INFRA_SERVER_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["server_url"])' "$SKILL_DIR/experiment_infra_credentials.json")"
export INFRA_SESSION_KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session_key"])' "$SKILL_DIR/experiment_infra_credentials.json")"
```

Check budget and remote setup:

```bash
"$SKILL_DIR/scripts/fast_query_budget.sh" --no-save
"$SKILL_DIR/scripts/fast_query_server_info.sh" --no-save
"$SKILL_DIR/scripts/fast_query_working_dir.sh" --no-save --max-depth 2
```

Expected useful facts:

- `allow_run_local: true`
- `allow_cloud: true` if testing SkyPilot
- `working_dir` is the assigned upload root
- Qwen model is listed in the remote Hugging Face/model setup
- the host has an available H100 in the allocated policy

Push the inference workspace:

```bash
"$SKILL_DIR/scripts/fast_push_code.sh" \
  "$SKILL_DIR/assets/qwen_inference" \
  qwen_inference
```

## Mode 1: Direct Remote Execution

Use this mode first when the host conda env and host model path are enough.

Config shape:

```json
{
  "gpu": "H100:1",
  "data_version": "qwen2.5-7b-instruct-run-local-smoke-test",
  "estimated_hours": 0.25,
  "run_local": true,
  "use_spot": false,
  "local_use_bash": true,
  "strict_provenance": false,
  "cloud": "ssh"
}
```

YAML shape:

```yaml
name: qwen-inference-run-local

resources:
  cpus: 4+
  accelerators: H100:1

setup: |
  source /home/zsgpu/miniconda3/bin/activate
  conda activate r3l
  cd qwen_inference
  python -V
  python - <<'PY'
  import importlib.util
  import subprocess
  import sys

  missing = [
      package
      for package, module in (
          ("transformers>=4.40", "transformers"),
          ("accelerate", "accelerate"),
      )
      if importlib.util.find_spec(module) is None
  ]
  if missing:
      subprocess.check_call([sys.executable, "-m", "pip", "install", *missing])
  PY
  nvidia-smi
  test -d /mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct

run: |
  export HF_HUB_OFFLINE=1
  export TRANSFORMERS_OFFLINE=1
  python qwen_inference_test.py
```

Submit:

```bash
"$SKILL_DIR/scripts/fast_submit.sh" \
  --config "$SKILL_DIR/assets/qwen_inference/qwen_inference_run_local.conf.json" \
  --yaml "$SKILL_DIR/assets/qwen_inference/qwen_inference_run_local.yaml"
```

Poll:

```bash
"$SKILL_DIR/scripts/fast_query_exp_status.sh" RUN_ID --summary --no-save
"$SKILL_DIR/scripts/fast_query_exp_status.sh" RUN_ID --no-save
```

Observed successful run:

```text
run_id: run_ddcf176ff36c
status: succeeded
cluster_name: local
CUDA_VISIBLE_DEVICES: 2
cuda_available: True
cuda_device: NVIDIA H100 80GB HBM3
load_seconds: 3.92
generation_seconds: 0.84
```

Takeaway: in direct host execution, the policy-provided `CUDA_VISIBLE_DEVICES=2` works.

## Mode 2: SkyPilot Container Execution

Use this mode when container isolation matters. Be explicit about host mounts and GPU ordinal mapping.

Config shape:

```json
{
  "gpu": "H100:1",
  "data_version": "qwen2.5-7b-instruct-local-path-smoke-test",
  "estimated_hours": 0.25,
  "run_local": false,
  "save_log_to_workdir": true,
  "log_dir": "logs",
  "use_spot": false,
  "local_use_bash": true,
  "strict_provenance": false,
  "cloud": "ssh"
}
```

YAML shape:

```yaml
name: qwen-inference-runtime-docker

resources:
  infra: ssh/local-gpu
  cpus: 4+
  accelerators: H100:1
  image_id: docker:yangtzeailab/autoresearch-r3l:cuda12.9-py310
  use_spot: false
  autostop:
    idle_minutes: 20
    down: true

config:
  ssh:
    pod_config:
      spec:
        volumes:
          - name: data0
            hostPath:
              path: /mnt/data0
              type: Directory
        containers:
          - name: ray-node
            imagePullPolicy: IfNotPresent
            volumeMounts:
              - name: data0
                mountPath: /mnt/data0

workdir: qwen_inference

setup: |
  source /etc/profile.d/conda-env.sh
  python -V
  python - <<'PY'
  import importlib.util
  import subprocess
  import sys

  missing = [
      package
      for package, module in (
          ("transformers>=4.40", "transformers"),
          ("accelerate", "accelerate"),
      )
      if importlib.util.find_spec(module) is None
  ]
  if missing:
      subprocess.check_call([sys.executable, "-m", "pip", "install", *missing])
  PY
  nvidia-smi
  test -d /mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct

run: |
  source /etc/profile.d/conda-env.sh
  export CUDA_VISIBLE_DEVICES=0
  export HF_HUB_OFFLINE=1
  export TRANSFORMERS_OFFLINE=1
  python qwen_inference_test.py
```

Submit:

```bash
"$SKILL_DIR/scripts/fast_submit.sh" \
  --config "$SKILL_DIR/assets/qwen_inference/qwen_inference_skypilot_container.conf.json" \
  --yaml "$SKILL_DIR/assets/qwen_inference/qwen_inference_runtime_docker.yaml"
```

Poll:

```bash
"$SKILL_DIR/scripts/fast_query_exp_status.sh" RUN_ID --summary --no-save
"$SKILL_DIR/scripts/fast_query_exp_status.sh" RUN_ID --no-save
```

## Container CUDA Sanity Test

Before loading a large model in the container, run a tiny CUDA test:

```bash
"$SKILL_DIR/scripts/fast_submit.sh" \
  --config "$SKILL_DIR/assets/qwen_inference/qwen_inference_skypilot_container.conf.json" \
  --yaml "$SKILL_DIR/assets/qwen_inference/cuda_visible_runtime_docker.yaml"
```

Expected pass lines:

```text
before CUDA_VISIBLE_DEVICES=2
after CUDA_VISIBLE_DEVICES=0
cuda_available: True
cuda_device_count: 1
cuda_device_name_0: NVIDIA H100 80GB HBM3
cuda_tensor_sum: 56
```

Observed successful CUDA test:

```text
run_id: run_50e60643f24c
status: succeeded
```

## Failure Modes And Fixes

Setup fails before Python inference starts:

- Check whether the container has `transformers` and `accelerate`.
- Check whether `/mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct` exists inside the container.
- For SkyPilot, add a `/mnt/data0` hostPath mount.

`nvidia-smi` sees an H100 but PyTorch says `cuda_available: False`:

- Check `CUDA_VISIBLE_DEVICES` in the Python process.
- In the tested container, the host policy set `CUDA_VISIBLE_DEVICES=2`, while the container saw the assigned GPU as ordinal `0`.
- Fix by setting `export CUDA_VISIBLE_DEVICES=0` inside the container `run` block.

Model generation is very slow:

- It may be running on CPU fallback.
- Confirm `cuda_available: True` before loading the model.
- Run `cuda_visible_runtime_docker.yaml` before the full model test.

Log tail is too noisy or truncated:

- Use `--summary` for frequent polling.
- Print a clear final summary block from the Python script.

## Minimal Reproduction Order

1. Query budget and remote setup.
2. Push `assets/qwen_inference` to `qwen_inference`.
3. Run `cuda_visible_runtime_docker.yaml` if using SkyPilot container mode.
4. Run `qwen_inference_run_local.yaml` for direct host execution, or `qwen_inference_runtime_docker.yaml` for container execution.
5. Poll with `fast_query_exp_status.sh RUN_ID --no-save`.
6. Report `run_id`, status, CUDA visibility, load time, generation time, and the answer.
