# 65816X: session notes

65816X is an enhanced SNES in Verilog for a Lattice ECP5 FPGA. The CPU is a 65C816 with optional extensions. The repository is `f-accomando/65816X`. Reply in the language of the message of the user. The user usually writes in Italian.

## 1. Find information

Read files in small slices (`grep`, or `offset` and `limit`). The current state is in `docs/progress/<area>.md`. The areas are [`cpu`](docs/progress/cpu.md) and [`system`](docs/progress/system.md).

| Need | Command or file |
|---|---|
| Open work of an area | `grep -n -A 20 '^## Open work' docs/progress/<area>.md` |
| Binding rules of an area | `grep -n -A 20 '^## Rules' docs/progress/<area>.md` |
| CPU compatibility score | `make cpu`, then `build/cpu_score.txt` |
| CPU score on the public vectors | `make cpu-public SST=../65816-test-vectors SST_FLAGS=--bus`, then `build/cpu_public_score.txt` |
| Owner decisions and open questions | `HANDOFF.md`, sections 3 and 9 |
| Phases of the project | `docs/ROADMAP.md` |
| Bus, memory map, opcodes, extensions | `docs/ARCHITECTURE.md` |
| Check commands, synthesis budget, measured results | `docs/VERIFICATION.md` |
| Variants A and B, resource estimates | `docs/VARIANTS.md` |
| User manual: text, build, rules | `manuals/README.md` |
| Design of the new CPU core, work orders | `docs/design/cpu-core.md` |

## 2. Rules

**Branches**
- When: Open a branch only when the user asks for development work (feature, fix, or refactor). For questions, analysis, research, and reads, stay on the current branch.
- Name: Use `claude/<descriptive-name>`. If the purpose, area, or name is not clear, ask the user before you create the branch or change files. If the session names a branch, use only that branch.
- Base: Start from an up-to-date `main`.
- Integrate: Wait until `make check` passes and the CI of the branch is green. Then merge the branch into `main` with a fast-forward. Push `main`. Do not open a pull request. Then delete the branch (remote and local) and its worktree, each by name.

**Tests.** During the work, run only the targets that the change affects: `make cpu` (CPU), `make test` (system), `make unit` (one module), `make synth` (resources). On Windows, run the targets in WSL.

**Estimates and facts.** Write "estimate" next to a number that no tool measured. State what is not verified.

**Licenses and security.** Sources contain only original code or code with a permissive license. Keep third-party test vectors outside the repository. Keep secrets, such as `*_KEY` and tokens, outside the repository.

**Units.** Write sizes as KB, MB, and GB. Each unit is a power of 1024 (1 MB = 1048576 bytes). Do not write KiB, MiB, or GiB.

**Language of the documents.** Write every `.md` file that directs the project in English, with ASD-STE100. These files are `CLAUDE.md`, `README.md`, `HANDOFF.md`, and all files in `docs/`. Write the manual in the same style.

**Manual.** Keep the user manual true. Update `manuals/content/en/65816x.md` in the same change that changes what a user sees or does. Then run `make manual`.

**ASD-STE100.** Write short sentences: 20 words maximum for an instruction, 25 words maximum for a description. Write one instruction in each sentence. Use the active voice. Use imperative verbs for instructions. Use one word for one meaning. Write 6 sentences maximum in a paragraph.

**Writing rules.** State each rule as an action. Delete a retired rule. A negation keeps the old behavior in view. Add a prohibition only when an action keeps harming development despite the positive rule. Write the harm next to it.

## 3. Task closure

Before you declare a task complete, do these steps:

1. Update the status. Remove the completed items and update the partial items in `## Open work` of the area file `docs/progress/<area>.md`.
2. Update the rules. If you add or change an architectural constraint, record it in `## Rules (do not break)` of the same file.
3. Update the manual. Run `make manual-check`. Read each changed source, correct the text, and run `make manual`.
4. Run `make check`. All targets must pass.
5. Check consistency. Find changes to the bus, the memory map, a register, an opcode, an extension, or a `make` target. Update the related documents of section 1.
6. Check CI. If you change `.github/workflows/` or the `check` target, make the CI run the same targets as `make check`.

## Glossary

- `Necessity`: a score from 1 to 5. Declare it before you use an expensive model. State one reason: a cheaper model failed, or an error is costly.
- **Autonomy threshold = 4** (user preference). With N = 1 to 3, use the standard model. With N = 4 or 5, switch to the expensive model without asking. State the score and the reason in the chat. To change the threshold, edit this line.
