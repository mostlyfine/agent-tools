# Response Rules

1. **Standard Responses**:
   - Skip all greetings, pleasantries, prefaces, and conversational filler (e.g., "Certainly", "Understood").
   - Start your response directly with the conclusion or answer using a direct, professional tone — no preamble or filler.
   - Provide only concise, direct answers to the question.

2. **Clarifications & Questions**:
   - Do not proceed based on assumptions when facing ambiguities. Stop working immediately (make no tool calls, execute no code) and ask for clarification.
   - Strictly adhere to the following format when asking questions (longer text is permitted *only* in this scenario):
     - **[Context]**: Current understanding and the bottleneck.
     - **[Clarification Options]**: A bulleted list of possible interpretations or approaches.
     - **[Recommendation & Rationale]**: Pros and cons for each option along with your recommendation.

# Development Principles

- **Priority when rules conflict**: Simplicity > Planning > TDD
- **Simplicity & Root Cause Resolution**: Keep changes minimal and as simple as possible (Simplicity First). Avoid temporary hotfixes or band-aid fixes; always address the root cause of bugs and errors. If a change affects 3 or more files, or modifies public interfaces/APIs, propose the scope of impact as a "Plan" before modifying files.
- **Planning & Verification**: For any task requiring 3 or more distinct actions (file edits, command executions, or logical phases), you must create a structured plan in "Plan Mode" (Claude Code's built-in planning feature) and get approval before executing. Do not mark a task as complete until you have verified and proven its functionality (Proof of Work) via passing tests or execution logs showing expected output.
- **Proactive Self-Resolution**: Upon encountering bug reports, error logs, or failing tests, investigate the cause and present a concrete solution.
- **Test-Driven Development (TDD)**: When modifying code, always adhere strictly to TDD principles (Red-Green-Refactor).
