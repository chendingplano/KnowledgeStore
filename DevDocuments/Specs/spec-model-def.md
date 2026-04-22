# Model Configurations (.models.toml)
The system may use different LLM models for different purposes. An LLM model is defined by four environment variables:
- Model Name
- Model Base URL
- Model API Key
- Model Timeout

Each model has a logic name. Applications use logic name to pick LLM models.

Models are defined in .models.toml, which should not be excluded in GIT.

Example:
```text
[gemma4-26b]
host            = "ollama"
model_name      = "gemma4:26b"
api_key         = "ollama"
base_url        = "http://127.0.0.1:11434"
timeout_sec     = 100

[gpt-5-4-mini]
host            = "cloud"
model_name      = "gpt-5.4-mini"
base_url        = "https://api.openai.com"
timeout_sec     = 100
api_key         = "sk-proj-...iM1REA"
```

# Use Models

Applications can use environment variables to specify the model to use. For instance, topic-driven chunking 
needs to use an LLM. It uses the env variable SEMANTIC_CHUNKING_MODEL_NAME, such as:
```text
SEMANTIC_CHUNKING_MODEL_NAME = "gpt-5-4-mini".
```