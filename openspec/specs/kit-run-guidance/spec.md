# kit-run-guidance Specification

## Purpose
Keeps the run guidance this repository publishes — the build script's closing hint and the
README quick start — pointing at kit directories that exist, in the argument form the
sandbox CLI accepts today.

## Requirements

### Requirement: Published run guidance names kits that exist
Every run instruction this repository publishes SHALL name a kit path that exists in this
repository, or a placeholder that is clearly marked as one.

#### Scenario: Build script closes with a real kit path
- **WHEN** the build script finishes a successful build
- **THEN** the closing run hint names a kit path under `kits/` that exists in the repository
- **AND** it does not name a root `kit/` directory

#### Scenario: README quick start uses a real kit path
- **WHEN** a reader follows the README manual build steps to the run step
- **THEN** that step shows a kit path under `kits/` that exists in the repository
- **AND** it does not show `sbx run ./kit`

### Requirement: Run guidance uses the current sandbox CLI argument form
Published run guidance SHALL present the sandbox run command in the positional kit and
workspace form the CLI accepts today, consistently wherever it appears.

#### Scenario: Quick start matches the form used later in the README
- **WHEN** a reader compares the README quick start run step with the kit invocation shown in the Copilot section of the same file
- **THEN** both show the same argument order: sandbox name, then kit path, then workspace
- **AND** neither relies on the deprecated kit flag
