# Contributing

Talkboard began as a parent's attempt to build an AAC tool for their child.
Parents, teachers, caregivers, AAC users, speech-language pathologists,
accessibility specialists and developers are invited to help it improve.

## You do not need to code

Open a [GitHub issue](https://github.com/brendanphall/talkboard/issues) to share:

- Something that makes a communication board easier or harder to use at home or school.
- An accessibility barrier, confusing interaction or missing caregiver workflow.
- Research or professional guidance that supports or challenges a design decision.
- Ideas for vocabulary organization, modeling, personal expression or practical activities.
- Documentation improvements or suggestions for a matching printed board.

Describe the situation and what you would like to be different. Share only what
you are comfortable making public; leave out identifying information, personal
media and education or clinical records. A synthetic example is enough.

When suggesting an educational or AAC practice, explain whether it comes from
personal experience, professional guidance or research, and link a source where
available. One person's experience can inform a design discussion without being
a claim that the approach will work for everyone.

## Code contributions

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

## License

The project uses Apache License 2.0. Contributions intentionally submitted for
inclusion are covered by its contribution terms (Section 5), unless explicitly
stated otherwise. Submit only work you have permission to contribute, and retain
required notices for any third-party material.
