# Sandbox Docker (created by OpenClaw)

Location: ~/.openclaw/workspace.

| Command | Explanations |
|:--------|:-------------|
| docker compose -f .devcontainer/docker-compose.yml build | Build the docker |
| docker compose -f .devcontainer/docker-compose.yml up -d | Start the docker |
| docker compose -f .devcontainer/docker-compose.yml down | Stop the docker |
| docker compose -f .devcontainer/docker-compose.yml ps | View docker status |
| docker compose -f .devcontainer/docker-compose.yml logs -f | View logs |
| docker compose -f .devcontainer/docker-compose.yml exec dev bash | Go to the docker (a shell) |