# Contributing

Small, focused improvements are welcome. Explain the observable behavior and
run the relevant tests before submitting a pull request.

- Preserve cell coordinates, concept identity and separate label/spoken text.
- Communication must remain available independently of caregiver editing access.
- Validate imports completely and preserve the current board on failure.
- Use invented labels and synthetic media in tests and bug reports.
- Keep automated output silent. Never include signing material or personal data.
- Edit `project.yml`, then regenerate Xcode. Generated project/build files are ignored.
- Keep pure model and policy logic in TalkboardCore and platform adapters in App.

Use GitHub issues for reproducible problems. Include expected/actual behavior,
iPadOS/Xcode versions and minimal synthetic reproduction steps. Remove personal
content and identifiers from screenshots and logs before sharing them.
