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
      Done except the `sbx` half (2026-10-11, second rebuild, sandbox `sbx-pi`, docker 29.8.1
      with its own store). This task, not the stubbed checks in 1.2 / 2.1 / 3.1, is what
      validates that the image build accepts `--build-arg OPENSPEC_VERSION=<pin>` and that a
      printed run hint works against a real sandbox runtime; those stubbed checks prove the
      argument vector and the printed paths only.

      Runtime measured inside the rebuilt sandbox, the first measurement of the pinned CLI in
      a real `sbx` runtime rather than plain Docker: image `sbx-pi:1.1.0` plus `sbx-pi:latest`
      (`out/sbx-pi-v1.1.0.tar`, `RepoTags ["sbx-pi:1.1.0","sbx-pi:latest"]`, image config
      created `2026-10-10T23:02:23Z`), `pi --version` -> `1.1.0`, `openspec --version` ->
      `1.14.1`, `openspec schema which spec-driven` -> `Source: user`, path
      `/home/agent/.local/share/openspec/schemas/spec-driven`, shadowing the package schema.
      The baked override is active, so the largest open assumption in the change holds.
      `/opsx-propose` is offered: RPC `get_commands` (`printf '{"type":"get_commands"}\n' |
      timeout 120 pi --mode rpc --no-session`) returned 56 commands, 9 of them `opsx-*`, each
      with `scope: project` under `/home/jonas/dev/sbx-pi/.pi/prompts/`.

      Build half, real `docker build`, run from a scratch copy of the checkout (`Dockerfile`,
      `build.sh`, `README.md`, `scripts/`, `kits/`, `openspec/`; no `.git`, no `out/`, no
      `pi-agent-configs/`, so the 802 MB tar under `out/` was never touched and the build
      context stayed small). `printf 'n\nY\n' | source build.sh --version 1.1.0
      --openspec-version 1.14.0` produced a `docker build` that ran `npm install -g
      --ignore-scripts "@fission-ai/openspec@1.14.0"`: the pin reaches the install, the
      `Dockerfile` default `1.14.1` does not. That build then failed in the same `RUN`, at
      `patch_schema.mjs`: `anchor for 'task groups are vertical slices' matched 0 times,
      expected exactly 1`. The override is therefore locked to 1.14.1, and any other pin fails
      the image build at build time and loudly. See the follow-up note below.

      Second run, pin `1.14.1`: build succeeded, tags `sbx-pi:1.1.0` and `sbx-pi:latest`,
      3.39 GB unpacked, 802 MB tar, step 2 `docker image save` ok. `docker run --rm
      --entrypoint bash sbx-pi:1.1.0` then reported `openspec --version` -> `1.14.1`, which
      equals the pin, `pi --version` -> `1.1.0`, `openspec schema which spec-driven` ->
      `Source: user`, baked config `delivery=commands`, `profile=custom`, the 9-workflow list,
      and `openspec init --tools pi` in a clean `/tmp/ws` wrote exactly the 9 `opsx-*.md`
      prompt files and no `.pi/skills`. With no project, the same RPC call advertises 0 `opsx`
      prompts, so the prompts come from the project and not from the image. Say plainly: the
      init, schema-source, prompt-count, `.pi/skills`, and config checks above repeat what the
      `Dockerfile` build-time smoke layer (`Dockerfile:108-121`) already asserts, and that layer
      passed inside run 2 (`smoke: 9 prompt files, no .pi/skills, delivery=commands,
      profile=custom`). What this run adds over that layer is the pin differential between
      1.14.0 and 1.14.1, `pi --version` inside the image, and a container started from outside
      the build.
      Fidelity to the host-built image: 15 of 24 layers identical, divergence starts at the
      first npm layer, `PATH` and `Cmd` identical.

      Unpinned half, not re-measured with a real build: an unpinned run prints no
      `OPENSPEC_VERSION` token (stub evidence, 1.2 and 3.1) and `Dockerfile:16` is
      `ARG OPENSPEC_VERSION=1.14.1`, so an unpinned build installs 1.14.1. The running sandbox
      image reports 1.14.1, which is consistent with that but does not prove it.

      Step 2 and the run hint stopped before `sbx`, for a reason this run created. `build.sh`
      is a host script: it is meant to run outside a sandbox, and the operator confirmed that
      `sbx template load` inside a sandbox is expected to be impossible, not a defect. This run
      sourced it inside a sandbox from a wrapper that set `set -u` without exporting `USER`, so
      `build.sh:248` (`id -nG "$USER"`) printed `USER: unbound variable`, took the `sudo`
      branch, and left a root-owned `out/sbx-pi-v1.1.0.tar`; `build.sh:253` then expanded
      `"$USER":"$USER"` in `sudo chown` and aborted the sourced script with exit 1. Measured
      with `env -u USER bash -c 'set -uo pipefail; if id -nG "$USER" | grep -qw docker; then
      ...'`. The account is in the docker group (`id -nG` -> `agent sudo docker`), so a normal
      host shell, where `USER` is set, takes the plain branch and hits none of this. No change
      to `build.sh` follows from it.

      Still open, and it cannot close here: `sbx template load` and the first `sbx run`. `sbx`
      is a host CLI and is not available inside a sandbox (`command -v sbx` -> nothing), and
      `build.sh` is a host script. That half of 3.2 needs a host, so the 2.1 kit run hint was
      never pasted into a shell by any run so far.
- [x] 3.3 Sweep the two in-scope files for leftover stale guidance. Verify:
      `grep -rn "sbx run .*kit" build.sh README.md` lists only kit paths that exist under
      `kits/` or clearly-marked placeholders, and `pi-agent-configs/README.md`, `Dockerfile`
      and `scripts/openspec/` appear unchanged in `git status` (that repository's
      `sbx-pi:0.83.0` line stays as it is, per the proposal's exclusions).

## Review round (2026-10-11)

Two read-only reviewers reviewed commit `a2d480e`. Both hit their time limit before writing a
report file, so their findings were recovered from the run transcripts and re-checked by the
coordinator before anything was applied.

- Applied, source leak. `build.sh` is sourced, so an exported `OPENSPEC_VERSION` stays set in
  the shell and applies to every later build. Measured: after `export
  OPENSPEC_VERSION=0.1.0-legacy`, `source build.sh --version 0.85.1 --git-user-name a
  --git-user-email b@x` produced `--build-arg OPENSPEC_VERSION=0.1.0-legacy`. This is the
  behaviour `specs/image-build-version-pinning/spec.md` requires for an exported override, so
  no code guard was added. README "Bump OpenSpec" now says to `unset OPENSPEC_VERSION` or
  build in a subshell.
- Applied, run hint. The hint printed `${kit_dir} <workspace>`. It prints `'${kit_dir}' .`
  now, which matches README.md:41: one placeholder instead of two, and a kit path with a space
  survives the paste. Measured: a bare `<name>` placeholder is shell input redirection and
  fails with `sandbox-name: No such file or directory`, so the pasted line never silently does
  the wrong thing. The remaining `<sandbox-name>` placeholder stays, because the spec allows a
  clearly marked placeholder and the script cannot know the sandbox name.
- Declined, design note. The reviewer claimed `design.md` states the wrong failure mode for a
  flag with no value. Re-measured: `--openspec-version` with no value exits 1, prints nothing,
  and runs no build; `--version` behaves the same. `design.md` is correct as written. The wrong
  claim came from the coordinator, who measured with `source ./build.sh ... | head`, which puts
  the sourced script in a subshell pipeline and reports the status of `head`.
- No action. A bad pin version fails at `Dockerfile:87`, where `npm install -g
  "@fission-ai/openspec@${OPENSPEC_VERSION}"` fails the build. That is loud and at build time.
  The `--help` fix stays in this commit: task 1.3 cannot be verified without it.
- Out of scope, left as a follow-up. The doc sweep found `scripts/openspec/README.md` names
  only the `--build-arg` form of the pin. Adding the script form there is correct but outside
  the files this change declared, so it was reverted and not committed.

## Workflow follow-up

- Implement with `/opsx-apply fix-build-pin-and-kit-paths`, keeping edits inside `build.sh`
  and `README.md`.
- Run `/opsx-verify fix-build-pin-and-kit-paths` against the specs before review.
- Archive with `/opsx-archive fix-build-pin-and-kit-paths` only after the change is reviewed
  and merged, then confirm the two new capability specs landed under `openspec/specs/`.
