# SAITEC Git Branch Law

## Article 1. Main branch
- `main` is the only long-lived branch.
- Direct development on `main` is forbidden.

## Article 2. Allowed branch names
- All development branches must be created from `main`.
- Only the following branch names are legal:
  - `feat/<topic>`
  - `fix/<topic>`
  - `new/<topic>`
- `<topic>` must be lowercase and may only contain letters, numbers, `.`, `_`, and `-`.

## Article 3. Merge path
- Changes enter `main` through Pull Requests.
- Direct pushes to remote `main` are forbidden.

## Article 4. Enforcement boundary
- Local Git hooks enforce branch naming and block direct pushes to `main`.
- Pull Request approvals, conversation resolution, and required status checks remain platform rules and must be enforced in GitHub settings.
