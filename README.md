# mcptask-releases

Released binaries of the **mcptask runner** — the tool that drives Claude Code
through the tasks on [mcptask.online](https://mcptask.online).

This repository holds no source. It exists so the binaries can be downloaded
without a token: the runner is developed in a private repository, and a private
repository's release assets cannot be fetched anonymously, which would rule out
a one-line install. The artefacts are the public part.

## Install

```bash
curl -fsSL https://github.com/jchsoft/mcptask-releases/releases/latest/download/install.sh | sh
```

macOS and Linux, amd64 and arm64. The script detects the platform, verifies the
download against the release's `checksums.txt`, and installs `mcptask_runner`
into `/usr/local/bin` when that is already writable and `~/.local/bin`
otherwise. It never calls `sudo`, and it installs the binary and stops — it does
not run `init` and does not enable a scheduled job.

Read it before you run it: [`install.sh`](install.sh) is the same file the
command above fetches.

| Variable | Effect |
| --- | --- |
| `MCPTASK_VERSION` | install a specific tag instead of the latest release |
| `MCPTASK_INSTALL_DIR` | install somewhere else |

On Windows, download the `windows` archive from
[Releases](https://github.com/jchsoft/mcptask-releases/releases) and put
`mcptask_runner.exe` on `PATH`.

## Verifying a manual download

Every release publishes `checksums.txt` alongside the archives.

```bash
shasum -a 256 --ignore-missing --check checksums.txt   # sha256sum -c on Linux
```

Worth doing: the binary goes on to run your Claude sessions with your
credentials.

## Getting started

```bash
mcptask_runner init      # in the project you want the runner to work on
mcptask_runner version
```

## MCP server

mcptask.online is itself a remote MCP server — the runner is one client of it,
Claude Code, Claude.ai, ChatGPT and any other MCP client can connect directly.

| | |
| --- | --- |
| Endpoint | `https://mcptask.online/mcp` (Streamable HTTP) |
| Authentication | `Authorization: Bearer <token>` or OAuth; without a token `/mcp` answers `401` with `WWW-Authenticate` |
| Server card | [`/.well-known/mcp/server-card.json`](https://mcptask.online/.well-known/mcp/server-card.json) — every tool and resource |
| Registry entry | [`server.json`](server.json) (`online.mcptask/mcptask`) |

Put this in the project's `.mcp.json` and export your token as `MCPTASK_TOKEN`:

```json
{
  "mcpServers": {
    "mcptask-online": {
      "type": "http",
      "url": "https://mcptask.online/mcp",
      "headers": {
        "Authorization": "Bearer ${MCPTASK_TOKEN}"
      }
    }
  }
}
```

Where to get the token and how to wire up each client:
[mcptask.online/installation](https://mcptask.online/installation?language=en).

---

Issues and questions: [mcptask.online](https://mcptask.online). Proprietary —
© JCHSoft. All rights reserved.
