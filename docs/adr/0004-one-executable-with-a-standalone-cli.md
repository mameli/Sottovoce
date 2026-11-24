# One executable, with a CLI that works without the app

As in Takku, one executable is the app, the CLI and the MCP server (`sottovoce mcp`). Unlike Takku, where commands that change something go through the running app (Takku ADR 0015), the CLI transcribes in its own process without opening a window, so an agent can run `sottovoce film.mov` from a terminal and get the Subtitle File back.
