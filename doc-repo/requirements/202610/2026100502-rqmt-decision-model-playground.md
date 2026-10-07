# Requirements for 'Decision Model Playground' page

- Document ID: `2026100502-rqmt`
- Status: Proposed
- Date: 2026-10-05
- Audience: Product owners, subject-matter experts, designers, developers, testers, and operators

## 1. Purpose
The page is designed for developers to test decision models.
It is bound to 'ChenWeb/development, System Admin => LLM => Decision Models => Playground'.

## 2. Features

### 2.1 Run a Decision
It lets users run a real decision-request.
The page has the following controls:
- A pulldown menu to let users select a model (models are defined in 'ChenWeb/.models.toml')
- A pulldown menu to let users select a policy (refer to '2026100503-devdoc')
- A pulldown menu to let users select request type (refer to '2026100502-devdoc' for request types)
- A text area to view/edit policy
- A text area to let users enter questions
- A button 'Add Question' to add a question to a Question List based on the entered content
- A button 'Run' to run the decision.
- An area to show the results of the responses from the decision model