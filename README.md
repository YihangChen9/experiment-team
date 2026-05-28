# experiment-team — Stage 6 multi-talent repo

A **multi-talent** Talent Market repo that ships the two specialists Stage 6 (Auto Experiment) needs in an adversarial research pipeline. Each talent is a separate directory with its own `profile.yaml`, registered under its own `talent_id` on Talent Market.

## Talents

| Directory | talent_id | Owns | Skill |
|---|---|---|---|
| [`experiment-code-writer/`](./experiment-code-writer) | `experiment-code-writer` | Stage 6a (Implementation): translate Stage 5 prose plan into runnable Python | `code_implementer` |
| [`experiment-runner/`](./experiment-runner) | `experiment-runner` | Stage 6b (Execution): drive remote experiment HTTP API end to end | `experiment_runner` |

## Why a multi-talent repo

Stage 6 splits into two sub-phases (impl + exec) with very different skill sets:

- **Code Writer** needs Python + research-spec translation chops, low temperature for deterministic implementation, and knowledge of smoke-mode + chat-template conventions.
- **Runner** needs infra/HTTP API discipline, secret-handling, and polling/cancel semantics — closer to DevOps than data science.

Shipping them as two separate talents from one repo means:

1. They version together — when the code-writer's `smoke` contract changes, the runner's `exec` contract changes too; one repo, one PR.
2. The market exposes both with their own pricing, descriptions, and avatars.
3. Pipeline engines that route impl/exec to different employees hire each talent independently.

`clone_talent_repo` handles the multi-talent layout: it iterates the repo's subdirs, reads each `profile.yaml`'s `id`, and caches each talent at `_TALENTS_CLONE_DIR / <id>/`.

## Install

Register the repo URL on [Talent Market](https://one-man-company.com/) once — the market discovers both talents automatically:

```
Add Talent → paste https://github.com/YihangChen9/experiment-team
```

Both `experiment-code-writer` and `experiment-runner` then become hireable by their respective `talent_id`.

## Repo layout

```
experiment-team/
├── README.md
├── LICENSE
├── experiment-code-writer/
│   ├── profile.yaml             id: experiment-code-writer
│   ├── DESCRIPTION.md           verbatim copy of the code-implementation-runbook
│   ├── avatar.jpg
│   ├── skills/
│   │   ├── core.md
│   │   └── code-implementation-runbook/
│   │       └── SKILL.md         Stage 6a implementation runbook
│   └── tools/
│       └── manifest.yaml
└── experiment-runner/
    ├── profile.yaml             id: experiment-runner
    ├── DESCRIPTION.md           verbatim copy of the experiment-execution-runbook
    ├── avatar.jpg
    ├── skills/
    │   ├── core.md
    │   ├── experiment-execution-runbook/
    │   │   └── SKILL.md         Stage 6b execution orchestrator runbook
    │   └── experiment-infra/    HTTP API runbook + fast_*.sh scripts + assets
    │       ├── SKILL.md
    │       ├── scripts/         fast_query_budget / fast_submit / fast_query_exp_status / fast_cancel / ...
    │       ├── assets/          base.conf.json + run YAMLs + sample Python scripts
    │       ├── references/      exp-configuration docs + runtime_images.json
    │       ├── receipt/
    │       └── experiment_infra_credentials.example.json   (real credentials NEVER committed)
    └── tools/
        └── manifest.yaml
```

## Upstream source

Extracted from the OneManCompany AutoResearch pipeline at <https://github.com/Memento-Teams/Memento-Research>. The runbooks are byte-identical to that repo's `feat/stage6-implementation-subphase` branch:

- `experiment-code-writer/skills/code-implementation-runbook/SKILL.md` ← `src/onemancompany/default_skills/code-implementation-runbook/SKILL.md`
- `experiment-runner/skills/experiment-execution-runbook/SKILL.md` ← `src/onemancompany/default_skills/experiment-execution-runbook/SKILL.md`
- `experiment-runner/skills/experiment-infra/` ← `src/onemancompany/default_skills/experiment-infra/` (with the real credentials file stripped)

## License

See [LICENSE](./LICENSE).
