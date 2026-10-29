# Marketplace publishing

Prepared against the [Omarchy publishing guide](https://plugins.omarchy.org/publish.html) and [submission form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml).

## Repository checklist

- [x] Public repository: https://github.com/billybonks/omarchy-microsandobx-monitor
- [x] Root `manifest.json` with schema version, permanent namespaced ID, name, version, author, description, kinds, and QML entry point.
- [x] Publishing ID: `billybonks.microsandbox-monitor` (not the prototype's `local.microsandbox`).
- [x] README with supported platform, runtime version, build dependencies, installation, updates, disable/removal, and security boundaries.
- [x] MIT license; dependency licensing documented separately.
- [x] Installation does not edit the bar until the user explicitly runs `make enable`; no configuration reset, sudo, runtime installer, or automatic workload actions.
- [x] Optional root `preview.png` and expanded/collapsed README screenshots, supplied by the repository owner.
- [x] CI for Rust formatting, tests, Clippy, and source-package consistency.

Run the official validator against the final checkout on an Omarchy machine before submitting:

```sh
make test
make check
```

`make check` runs `omarchy plugin validate .` and `qmllint` with the installed shell's imports. CI's structural checks are supplementary; they do not replace the official validator or native desktop testing.

## Submission details

**Repository URL:**

```text
https://github.com/billybonks/omarchy-microsandobx-monitor
```

**Suggested title:** `Microsandbox Monitor`

**Category:** `Developer Tools`

**Tags:** `Bar`, `Quickshell`, `System` (the form permits at most three)

**Maintainer notes:**

> Native Omarchy bar widget with expandable sandbox cards, CPU/memory usage, resource allocation, published ports, and lifecycle controls. Linux/local-only, tested with Omarchy 4.0.4 and an existing msb 0.7.11 runtime. Uses a compiled Rust helper and the official SDK; QML is the UI layer.
>
> IMPORTANT: This plugin currently requires a source build. Users must clone the repository, review it, and run make test, make check, make install, then explicitly make enable. The repository does not ship a prebuilt helper and omarchy plugin add alone is not sufficient. No build hook, remote installer, runtime download, or separate service is run automatically. Please retain this requirement in any listing and confirm that source-build plugins are suitable for the marketplace's installation UX.
>
> The SDK uses the existing local runtime, firmware, and state. There is no cloud backend, network listener, or automatic lifecycle action. Starting a sandbox can perform the normal network activity dictated by its existing configuration. Interactive shell/log actions use the existing msb CLI and Omarchy terminal launcher. Removal is confirmed and never force-stops a running sandbox. Plugin code and preview images are MIT; the official SDK is Apache-2.0, and other dependencies retain their own licenses.

## Owner actions still required

- [ ] Review the final pushed commit, README, and previews.
- [ ] Confirm ownership/permission for code and screenshot assets in the submission form.
- [ ] Recheck the current submission form for changed requirements.
- [ ] Open the submission issue using the link above, choose category/tags, and paste the notes.
- [ ] Acknowledge that marketplace approval is **listing validation, not a security review**.

Preparing this file or pushing the repository does not submit an issue, create a release, or imply marketplace acceptance. The guide makes the preview optional and does not require a tagged release. Source-build acceptance remains a maintainer decision; do not advertise one-click installation before a compatible packaging/distribution path exists.
