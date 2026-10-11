# image-build-version-pinning Specification

## Purpose
Lets an operator pin the versions baked into a locally built sbx-pi template image through
the documented build entry point, instead of having to bypass it and hand-run the image
build.

## Requirements

### Requirement: Build entry point forwards every supported version pin
The build entry point (`build.sh`) SHALL accept an override for each version the image
build accepts as a build argument, including the OpenSpec CLI version, and SHALL pass a
supplied override through to the image build.

#### Scenario: OpenSpec version supplied as an option
- **WHEN** the operator runs the build script with the OpenSpec version option set to `1.14.1`
- **THEN** the image build command includes `--build-arg OPENSPEC_VERSION=1.14.1`

#### Scenario: OpenSpec version supplied in the environment
- **WHEN** the operator exports `OPENSPEC_VERSION` and runs the build script without the option
- **THEN** the image build command includes `--build-arg OPENSPEC_VERSION=<that value>`

#### Scenario: No OpenSpec version supplied
- **WHEN** the operator runs the build script with no OpenSpec version override
- **THEN** the image build command contains no `OPENSPEC_VERSION` build argument
- **AND** the image is built with the version default declared in the image definition

#### Scenario: Existing Pi pin is unaffected
- **WHEN** the operator supplies a Pi version and no OpenSpec version
- **THEN** the image build command still includes `--build-arg PI_VERSION=<supplied Pi version>`
- **AND** the image tags and saved archive path are unchanged from today

### Requirement: Version overrides are discoverable from the entry point
The build entry point SHALL list every version override it accepts, as both an option and
an environment variable, in its help output.

#### Scenario: Help lists both pins
- **WHEN** the operator requests the build script's help
- **THEN** the output names the OpenSpec version option and the `OPENSPEC_VERSION` environment variable
- **AND** it still names the Pi version option and the `PI_VERSION` environment variable
