fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios register

```sh
[bundle exec] fastlane ios register
```

Register the bundle IDs and app group in the developer portal

### ios signing

```sh
[bundle exec] fastlane ios signing
```

Create/refresh the distribution certificate and App Store provisioning profiles

### ios testers

```sh
[bundle exec] fastlane ios testers
```

Create the internal TestFlight group and add the given team members (EMAILS=a@x,b@y; default: you)

### ios invite

```sh
[bundle exec] fastlane ios invite
```

Invite someone to App Store Connect (Marketing role, La Popote only) so they can be an internal tester. EMAIL=… FIRST=… LAST=…

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a TestFlight build (internal testers)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
