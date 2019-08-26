# github-merge-all-upstream-pull-requests

## Usage

```txt
Retrieves all merge-requests for a given github repository and merges them to a local git repo.

Usage: github-merge-all-upstream-pull-requests.sh [options] <github-repo>

Where <repo> takes the shape 'vendor/project'

Options:"
  -h|--help      Print this help dialogue and exit
  -V|--version   Print the current version and exit
```

Usage example (after installation):

```
GITHUB_TOKEN="$(cat /path/to/secret/.github-token)" bash github-merge-all-upstream-pull-requests.sh kelseyhightower/nocode
```

## Install

@TODO: Create a dist version

```bash
bpkg --version || { curl -Lo- 'https://raw.githubusercontent.com/bpkg/bpkg/master/setup.sh' | bash; }
git clone https://github.com/potherca-bash/github-merge-all-upstream-pull-requests.git
cd github-merge-all-upstream-pull-requests
bpkh getdeps

```

Available as a [bpkg](http://www.bpkg.sh/)

```sh
bpkg install [-g] potherca/github-merge-all-upstream-pull-requests
```
