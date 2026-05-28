# Experiment configuration (reference)

Detail beyond the main `SKILL.md` workflow — JSON config vs YAML run definition, SkyPilot
container configuration, overrides, and push paths.

## Two layers

### JSON config (`--config PATH`)

Experiment setup consumed by the submit API. Default: `assets/base.conf.json` in the skill directory (bundled configs live under `assets/`, matching the Agent Skills layout).

`assets/base.conf.json` keeps `run_local: true` for direct remote execution. Use `assets/skypilot_container.conf.json` when the user specifically wants `run_local: false` SkyPilot container execution.

For SkyPilot container jobs, choose runtime images from `references/runtime_images.json` when possible
instead of inventing image names. That registry records the default image, `sky_image_id` values,
package notes, and any pod-config snippets needed by the local runtime. Open it before deciding
`resources.image_id`, image pull policy, or pod-config defaults for a server/container run.

### YAML run definition (`--yaml PATH`)

SkyPilot-style task spec describing resources and lifecycle. Bundled examples:
`assets/test_torch.yaml` (run-local smoke test), `assets/test_torch_runtime_docker.yaml`
(remote SSH-node-pool container smoke test), and `assets/memrl.yaml`.

The submit config decides how YAML is interpreted:

- With `run_local: true`, the remote API runs the YAML `setup` and `run` blocks directly in the assigned remote workspace; `resources` and container `image_id` are not used for SkyPilot provisioning.
- With `run_local: false`, the remote API submits the YAML as a SkyPilot task.
- For `run_local: false`, an optional top-level `infra_cluster_name` reuses an existing SkyPilot cluster listed by `fast_query_budget.sh` under `resources.sky_clusters.clusters`; prefer entries with `reuse_candidate: true`. `INIT` entries may still be usable but can wait for setup to finish.

Key fields:

- `resources` — `cpus`, `accelerators` (e.g. `H100:1`, `A100:8`).
- `infra_cluster_name` — optional API extension, not native SkyPilot YAML. Prefer a current-session cluster name from `fast_query_budget.sh` where `matches_prefix: true` and `reuse_candidate: true`; the API removes this field before submitting the YAML to SkyPilot.
- `resources.autostop.down: true` — for `run_local: false` SSH/SkyPilot container jobs, requests infra-managed teardown after the job completes and `idle_minutes` has elapsed. If combined with `infra_cluster_name`, the reused cluster's teardown timer is refreshed by each completed job on that cluster; omit `autostop` only when the cluster should persist until manual cleanup.
- `resources.image_id` — container image for SkyPilot container runs, for example `docker:yangtzeailab/autoresearch-r3l:cuda12.9-py310`. This is ignored by `run_local: true`. Prefer a `sky_image_id` from `runtime_images.json`.
- `config.ssh.pod_config` — Kubernetes-style pod customization forwarded to the SSH node-pool container runtime. Use this when a container job needs host-path mounts or container fields such as `imagePullPolicy`.
- `workdir` — directory uploaded to the remote as the run's working directory. For SkyPilot YAML
  submitted through the remote API, relative paths resolve under the assigned remote workspace.
  `workdir: .` uploads that assigned workspace to SkyPilot's `/root/sky_workdir`.
- `file_mounts` — extra `/remote/path: /local/path` pairs.
- `setup` — commands to run **before** the experiment. Example:

  ```bash
  source /home/zsgpu/miniconda3/bin/activate
  cd <project_path>
  uv sync
  ```

- `run` — commands to start the experiment. Example: `uv run train.py`.

If `workdir` or `file_mounts` already hydrate the remote with everything the run needs, you do **not** need `fast_push_code.sh` before submit.

For the run-local smoke test, push the bundled smoke script into the assigned remote workspace, then submit with the default config:

```bash
$SKILL_DIR/scripts/fast_push_code.sh \
  $SKILL_DIR/assets/torch_test.py \
  torch_test.py

$SKILL_DIR/scripts/fast_submit.sh \
  --config $SKILL_DIR/assets/base.conf.json \
  --yaml $SKILL_DIR/assets/test_torch.yaml
```

For the remote-container example, push the bundled smoke script into the assigned remote workspace first:

```bash
$SKILL_DIR/scripts/fast_push_code.sh \
  $SKILL_DIR/assets/torch_test.py \
  torch_test.py
```

Then submit:

```bash
$SKILL_DIR/scripts/fast_submit.sh \
  --config $SKILL_DIR/assets/skypilot_container.conf.json \
  --yaml $SKILL_DIR/assets/test_torch_runtime_docker.yaml
```

`test_torch_runtime_docker.yaml` uses `workdir: .`, so SkyPilot uploads the assigned remote workspace
to `/root/sky_workdir` in the container and runs `python torch_test.py` there.

### SkyPilot container pod config

For `run_local: false` container jobs, the YAML may include a `config.ssh.pod_config`
block. This block is passed to the SSH node-pool container runtime as pod configuration.
Use it when the default container does not see a required host path or when the container
needs a specific image pull policy.

Start from `references/runtime_images.json` when selecting an image. The file is structured like:

```json
{
  "default_image": "vllm_w_flashattn",
  "images": {
    "vllm_w_flashattn": {
      "sky_image_id": "docker:yangtzeailab/vllm_w_flashattn:cuda12.9-py310",
      "yaml_resources": {
        "image_id": "docker:yangtzeailab/vllm_w_flashattn:cuda12.9-py310"
      },
      "local_k3s_pod_config": {
        "ssh": {
          "pod_config": {
            "spec": {
              "containers": [
                {
                  "name": "ray-node",
                  "imagePullPolicy": "Never"
                }
              ]
            }
          }
        }
      }
    }
  }
}
```

Use `yaml_resources.image_id` under the YAML `resources` block. If the image has a
`local_k3s_pod_config`, merge it into the YAML `config` block alongside any extra volumes
or mounts your job needs.

The Qwen cached-model inference example mounts the host `/mnt/data0` root into the
container so `/mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct` resolves inside the job:

```yaml
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
```

Notes:

- `containers[].name` must match the runtime's container name. The bundled container examples use `ray-node`.
- `hostPath.path` is a host path on the remote server, not a path in the uploaded workdir.
- `volumeMounts[].mountPath` is where that host path appears inside the container.
- Add only the host roots the job actually needs. For model inference, mounting `/mnt/data0`
  was enough to expose the cached Qwen model path.
- If a container job reports `nvidia-smi` sees a GPU but PyTorch reports `cuda_available: False`,
  check `CUDA_VISIBLE_DEVICES`. In the observed SSH container runtime, a host allocation such as
  `CUDA_VISIBLE_DEVICES=2` could leak into a one-GPU container where the assigned GPU is visible
  as ordinal `0`. Setting `export CUDA_VISIBLE_DEVICES=0` in the YAML `run:` block fixed the
  PyTorch visibility check.

The full runnable Qwen example lives in `../assets/qwen_inference/qwen_inference_runtime_docker.yaml`;
the tutorial and observed run logs are summarized in `../receipt/qwen_inference.md`.

### Shell state persists across `setup` → `run`

The runner concatenates the two blocks into a single bash script, so `cwd`, environment variables, and shell options set in `setup:` are still in effect when `run:` starts. If `setup:` ends with `cd experiments`, `run:` begins inside `experiments/` — do **not** re-`cd` into it. A second `cd experiments` will look for `experiments/experiments` and fail with `No such file or directory`.

### Where results live

For local runs (`run_local: true`), the submit/status API response's `metrics` and `output_s3` fields stay empty — final results are only in the run's stdout, exposed via `log_tail`. Two implications:

- Have the training script print a clearly delimited summary block at the end (e.g. `--- val_bpb: ... ---`) so it survives the ~32 KB API `log_tail` cap.
- For checkpoints and other large artifacts, write them to disk on the remote and set `output_s3` in the JSON config so they're surfaced through the API.

For SkyPilot container runs, `assets/skypilot_container.conf.json` sets `save_log_to_workdir: true` and `log_dir: "logs"`.
When job-log capture is available, actual SkyPilot job output is copied to `{log_dir}/{run_id}.log`
under the assigned remote workspace and the latest tail is mirrored into status `log_tail`.

## Overrides

- `-c` / `--cmd "CMD"` — non-empty value overrides the config's `run_command` for this invocation. When set, **YAML is ignored for the command path** (resources/setup from YAML still apply only if `run_command` is empty). Separate multiple shell commands with `;`.
- `--url URL` / `--key KEY` — per-invocation overrides for `INFRA_SERVER_URL` / `INFRA_SESSION_KEY`. Otherwise the script uses env vars (or the credentials file loaded into env per `SKILL.md`).

## Push Path Errors

The API only accepts uploads under the assigned remote workspace/upload root. If `fast_push_code.sh`
fails with a path error, re-upload using the directory named in the API error message.
