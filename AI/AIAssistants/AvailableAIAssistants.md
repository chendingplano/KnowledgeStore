# 1 Overview

This document describes the Coding Assistant available in the dev environment.

Currently, there are five coding assistant:
1. Claude Code  
2. Qwen Code  
3. OpenCode 
4. Codex
5. Crush 

# 2 Coding Assistants
## 2.1 Claude Code  

Currently, I am using the $20 plan. This is my major coding assistant.

## 2.2 Qwen Code  

This is my second coding assistant.

Note: The QWEN.md in ~/.qwen/ contains workspace-wide documentation (Go workspace, shared library, etc.). It’s still useful as a reference, but Qwen Code won’t automatically read it when you’re in a project directory. If you want project-specific guidance, each project (tax/, ChenWeb/) should have its own CLAUDE.md or .qwen/QWEN.md.

## 2.3 OpenCode 

Installed on 2026/02/26. Begin testing and experiments.

### 2.3.1 Cache inputs 

Added a feature to cache user inputs.

## 2.4 Codex 

This is from OpenAI. Would like to use it more. 

## 2.5 Crush 

This is a coding assistant written in Go. Plan to see whether I can use it as my major personalized coding assistant.

# 3 Utilities

## 3.1 rtk 

**Location**: ThirdParty/rtk <br>
**Installed**: 2026/02/28 <br>
**Status**: active

rtk is an open-source project, written in Rust, that sits between LLM and Claude Code. It intercepts
some of the tool uses to reduce the context usage. For more information, please read the docs in rtk/.

## 3.2 OpenViking 

**Location**: ThirdParty/openviking <br>
**Installed**: 2026/02/27<br>
**Status**: Just installed, not in use yet 