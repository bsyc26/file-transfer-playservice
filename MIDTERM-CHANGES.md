# Midterm experiment deployment changes

This fork evaluates the upstream service from commit `eeeda847d5cb5fc2e9d7476f270ccae42194efc1`. The Go implementation is unchanged. The experiment tools, written presentation and actual AWS evidence are in [the course repository's midterm-mastery/part2 directory](https://github.com/bsyc26/cs6650/tree/main/midterm-mastery/part2).

## Personal AWS account support

The starter expects Learner Lab's LabRole and an existing bucket. This fork adds optional Terraform settings so the same architecture can run in a personal account:

- `create_task_roles=true` creates an ECS execution role for image pulls and logs, plus a backend role restricted to reading the experiment S3 prefix. The gateway has no application task role.
- `create_files_bucket=true` creates a private, disposable fixture bucket. It uses force_destroy for reproducible test data; use a dedicated bucket containing only experiment fixtures.
- `allowed_account_ids` guards against applying the configuration in the wrong account.
- Task definitions depend on the execution and S3-read policies to avoid startup before permissions are attached.

Defaults for these options preserve the original Learner Lab workflow. The provider lock file pins the version used in the measured deployment. Inputs, credentials, plans and state are excluded from Git.

## Measured configuration

| Setting | Experiment value | Purpose |
|---|---|---|
| gateway_min / gateway_max | 1 / 1 | Hold gateway replica count fixed |
| backend_min / backend_max | 1 / 1 | Hold backend replica count fixed |
| Task size | 256 CPU units, 512 MiB per service | Same infrastructure across conditions |
| max_inflight | Default 4, compared with 2 | Measure admitted-transfer capacity |
| backend_workers | 8 | Hold command concurrency fixed |
| backend_send_loss | 0%, 1%, 5% | Measure recovery work |
| backend_recv_loss | 0% | Isolate send-loss changes |
| files | 4, 16, 64 KiB | Measure payload cost |

The course repository contains exact task-definition/environment manifests and image digests for each condition. Its README provides commands to build the images, generate fixtures, deploy, run the bounded tests and remove the stack. The build helper cross-compiles the unchanged Go packages for linux/amd64 and packages them in the starter's distroless runtime.

All dedicated AWS experiment resources were destroyed after collection. No live endpoint is maintained by this submission. Eight-slot and larger-file tests remain proposals, not measured results.
