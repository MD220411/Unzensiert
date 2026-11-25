# Security

Unzensiert runs a local model that refuses nothing, on your own computer, and it updates itself.
The protection is described in [docs/security.md](docs/security.md).

## Reporting a problem

Please report a security problem privately, not in a public issue:
[report a vulnerability](https://github.com/MD220411/Unzensiert/security/advisories/new) (the
"Security" tab of the repository, "Report a vulnerability"). Say what happens, how to repeat it and
which version (`VERSION` in the program folder) you use. A fix comes as a new release; a hole is
described in public only after installations had the time to update.

## Supported versions

Only the newest release gets fixes. Installations with automatic updates install it by themselves
(`unzensiert --update` does it at once).

## Releases

Every release is signed with the release key of the maintainer (`release.json` and
`release.json.sig`). Updates and the one-line installer install only a release whose signature
verifies with a key in `config/release-keys.json`; how that works is in
[docs/security.md](docs/security.md#signed-releases). Published releases cannot be changed.
