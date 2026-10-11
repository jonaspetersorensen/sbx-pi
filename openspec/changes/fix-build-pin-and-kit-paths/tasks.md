# Tasks

Setup that cannot live inside the first slice: none. The tracer bullet needs no new
dependency, no schema or spec work, and no refactor of `build.sh`; the stub commands it runs
against are created in a scratch directory outside this repository and are never committed.

## 1. Tracer bullet — one pinned OpenSpec version reaching the image build

- [x] 1.1 Parse a new `--openspec-version VER` option in `build.sh` and honour an exported
      `OPENSPEC_VERSION`, storing both in one variable the way `--version` / `PI_VERSION`
      already do, and print the effective value in the `=== Summary ===` block only when an
      override was supplied. Verify: `bash -n build.sh` is clean, and in the stubbed run from
      task 1.2 the summary names the version that was passed and prints no OpenSpec line when
      the flag is omitted.
- [x] 1.2 Append `--build-arg OPENSPEC_VERSION=<value>` to `BUILD_ARGS` only when the value is
      non-empty, next to the existing `GIT_USER_NAME` / `GIT_USER_EMAIL` appends and before
      both `docker build` call sites, so the run reaches the real integration boundary.
      Verify with stub commands on `PATH` in a scratch copy of the checkout (a `docker` and an
      `sbx` script that print their arguments one per line and exit 0), run as
      `printf 'Y\n' | source build.sh --version <pi> --git-user-name a --git-user-email b@x --openspec-version 1.14.1`:
      the captured `build` line contains `--build-arg OPENSPEC_VERSION=1.14.1`. Repeat the
      same command with `--openspec-version` removed: the `build` line contains no
      `OPENSPEC_VERSION` token at all (not `OPENSPEC_VERSION=`), and the `--build-arg
      PI_VERSION=<pi>` entry plus the `-t sbx-pi:<pi> -t sbx-pi:latest` tags are unchanged.
- [x] 1.3 List the new option under `Options:` and `OPENSPEC_VERSION` under `Environment:` in
      `usage()`, keeping the existing `--version` / `PI_VERSION` lines. Verify:
      `source build.sh --help` prints a usage block that names both new entries and both
      existing ones, and returns without running any build step (stub `docker` captures no
      call).
      Note: this verify needed `-h | --help)` to `return` after `usage`. `usage`'s `return 0`
      returns from `usage` only, so the option loop had been printing the usage block forever
      and never returned; the help branch now returns from the script. One statement in
      `build.sh`, not a parser rework.
- [x] 1.4 In `README.md` "Bump OpenSpec", replace the sentence stating that `build.sh` does
      not expose `OPENSPEC_VERSION` with the sourced-script form
      `source build.sh --openspec-version 1.14.1`, leaving the explicit `docker build
      --build-arg OPENSPEC_VERSION=...` example in place. Verify: the flag and the env var
      named in the README are spelled exactly as `usage()` prints them (diff the two), and
      `grep -n "does not expose .OPENSPEC_VERSION" README.md` returns nothing.

## 2. Slice: the run hint names kits that exist

- [x] 2.1 Replace the closing `echo "To run the kit: sbx run ${SCRIPT_DIR}/kit"` in
      `build.sh` with one ready-to-paste line per directory under `${SCRIPT_DIR}/kits/`, in the
      positional form `sbx run --name <sandbox-name> <script dir>/kits/<kit>/ <workspace>`, and
      a single no-match line naming `kits/` when the glob finds nothing. Verify: in the stubbed
      run from task 1.2 every path the closing lines print passes `test -d`;
      `grep -n '/kit"' build.sh` and `grep -n 'run ./kit' build.sh` return nothing; and in a
      scratch copy with `kits/` temporarily renamed the closing lines name no path and do not
      claim a kit that is absent.
      Note: read "name no path" as "name no kit path", per design D4, which requires the
      no-match line to name `kits/` itself. Taken literally the two clauses contradict each
      other. With `kits/` renamed the closing lines print
      `No kit found under <script dir>/kits/`: no `sbx run` command, no `kits/<name>/` path,
      and no claim that a kit is present.
- [x] 2.2 In `README.md` manual step 3, replace `sbx run ./kit` with the same positional form
      and a real kit path, `sbx run --name <sandbox-name> ./kits/github-copilot/ .`. Verify:
      `test -d kits/github-copilot` passes, and the two run commands in the README (quick start
      and Copilot section) show the same argument order — name, kit path, workspace — with no
      `--kit` flag in either.

## 3. Integration check: unpinned behaviour and one unstubbed run

- [x] 3.1 Compare the full stubbed `docker build` and `docker image save` argument vectors for
      an unpinned run before and after both slices. Verify: the two vectors are identical
      (`diff` of the captured stub output is empty) for `source build.sh --version <pi>
      --git-user-name a --git-user-email b@x`, which is the "no OpenSpec version supplied"
      scenario in `specs/image-build-version-pinning/spec.md`.
- [ ] 3.2 Replace the `docker` stub with reality on a docker-capable machine: run
      `source build.sh --openspec-version <pinned>` once, then `sbx` against the loaded
      template and report `openspec --version` inside the sandbox. Verify: the reported version
      equals the pin, and an unpinned build reports the `Dockerfile` `ARG OPENSPEC_VERSION`
      default. Record in the change that this task, not the stubbed checks, is what validates
      the image build and a real `sbx run`.
      Not done here (2026-10-11): this sandbox has a docker daemon but not what the task
      needs. `timeout 90 docker pull alpine` succeeded (`Status: Downloaded newer image for
      alpine:latest`, exit 0), which is irrelevant to this image — `Dockerfile:11` is
      `FROM docker/sandbox-templates:shell-docker`, absent locally (`docker images` lists only
      `searxng/searxng` and the new `alpine:latest`), and there is no `sbx` on `PATH`
      (`command -v sbx` -> nothing), so neither the build half nor the `sbx run` /
      `openspec --version` half can run. The applying run was also told not to start an image
      build of this repo. This task, not the stubbed checks in 1.2 / 2.1 / 3.1, is what
      validates that the image build accepts `--build-arg OPENSPEC_VERSION=<pin>` and that a
      printed run hint works against a real sandbox runtime; those stubbed checks prove the
      argument vector and the printed paths only.
- [x] 3.3 Sweep the two in-scope files for leftover stale guidance. Verify:
      `grep -rn "sbx run .*kit" build.sh README.md` lists only kit paths that exist under
      `kits/` or clearly-marked placeholders, and `pi-agent-configs/README.md`, `Dockerfile`
      and `scripts/openspec/` appear unchanged in `git status` (that repository's
      `sbx-pi:0.83.0` line stays as it is, per the proposal's exclusions).

## Workflow follow-up

- Implement with `/opsx-apply fix-build-pin-and-kit-paths`, keeping edits inside `build.sh`
  and `README.md`.
- Run `/opsx-verify fix-build-pin-and-kit-paths` against the specs before review.
- Archive with `/opsx-archive fix-build-pin-and-kit-paths` only after the change is reviewed
  and merged, then confirm the two new capability specs landed under `openspec/specs/`.
