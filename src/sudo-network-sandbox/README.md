
# Sudo & Network Sandbox (sudo-network-sandbox)

Blocks sudo commands and limits network egress to only the specified domains. Useful for isolating AI agents.

## Example Usage

```json
"features": {
    "ghcr.io/middlendian/devcontainer-features/sudo-network-sandbox:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| allowedDomains | List of permitted domains for egress traffic (comma-separated) | string | - |

Only Debian and Ubuntu base images are supported currently.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/middlendian/devcontainer-features/blob/main/src/sudo-network-sandbox/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
