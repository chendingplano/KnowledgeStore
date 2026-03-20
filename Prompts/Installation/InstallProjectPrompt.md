
- Use this skill if user mentions: "install this project: <url>, project name is xxx"
- User must specify the project name. If not, prompt the user for a project name
- If the open-source project is a skill, install it in ~/Workspace/.agents/skills/<project_name>. Otherwise, install it in ~/Workspace/ThirdParty/<project-name>. If the project already exists, prompt the user and stop the installation.
- Create a mise.toml that contains all the relevant commands from cloning the project, to daily operations and save the mise.toml file in the project directory.
- Use bun instead of npm
- Use .venv for Python projects
- Write a markdown doc OPERATIONS.md for this project and save it in the project directory.