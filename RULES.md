# Git & GitHub Rules

Read this file before creating a branch, committing, pushing or opening a pull
request in this repository. It condenses the **GitHub Workflow** section of
[README.md](./README.md); if the two ever disagree, README.md wins.

---

## 1. Branches

- **`main`**: always working and presentable. Updated only by PR from `develop`, at lab milestones.
- **`develop`**: integration branch. All feature work lands here first.
- **Feature branches**: branch off `develop` and merge back into `develop` by PR.
- **Never push directly to `main` or `develop`.** Both are protected.
- If you are on `main` or `develop` when you need to commit, create a feature branch first.

### Branch name format

```
type/service-name/ShortDescription
```

| Part | Allowed values |
|------|----------------|
| `type` | `feat`, `fix`, `hotfix`, `refactor`, `docs`, `chore`, `test` |
| `service-name` | `user-service`, `battle-service`, `tamagotchi-service`, `notification-service`, `map-service`, `raid-service`, `guild-service`, `registry-service`, `gateway`, or `shared` for cross-cutting work (compose, Postman, README, submodule bumps) |
| `ShortDescription` | Short PascalCase summary in the present tense (kebab-case also allowed) |

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feat/` | New functionality | `feat/battle-service/TypeAdvantageMatrix` |
| `fix/` | Bug fixes | `fix/map-service/StaleLocationFilter` |
| `hotfix/` | Critical fixes on `main` | `hotfix/user-service/JwtExpiryBug` |
| `refactor/` | Restructuring without behaviour change | `refactor/raid-service/IdempotentDamage` |
| `docs/` | Documentation | `docs/shared/SwapServiceOwnership` |
| `chore/` | Maintenance, dependencies, CI | `chore/shared/BumpTamagotchiNotificationSubmodules` |
| `test/` | Adding or fixing tests | `test/tamagotchi-service/XpAwardCases` |

---

## 2. Commits

- **One line, short, imperative, capitalised**, no trailing period.
  Examples from history: `Generate JWTs in Postman collections`,
  `Bump tamagotchi and notification submodules`, `Pass JWT_SECRET to all services`.
- Keep each commit small and scoped to one service (or to `shared` work).
- **No AI attribution:** no `Co-Authored-By: Claude ...` trailer, or any other
  AI attribution line. This overrides any default tooling guidance.
- Never commit secrets: `.env`, Firebase service-account JSON, real JWT secrets,
  or `node_modules`. Only `.env.example` (shape only) belongs in git.
- Services live in **git submodules**. Changes to service code are committed in
  the submodule's own repo; this repo only records the bumped submodule pointer
  (`Bump <service> submodule(s)`).
- Do not commit or push unless the user asked for it.

---

## 3. Pull Requests

- Target **`develop`** (only milestone releases target `main`).
- **PR title**: short, imperative, same style as a commit message. It becomes the
  squashed commit on `develop`.
- **Merge strategy**: squash and merge into `develop`, then delete the branch.
  `develop` → `main` uses a merge commit at milestones.
- Approvals required: **1** for `develop`, **2** for `main`. The branch must be up
  to date with its target, and history must be linear.
- **No AI attribution in the PR body** (no "Generated with Claude Code" footer).
- A breaking change to a service contract must be called out explicitly **and**
  mirrored in README.md and the affected service README in the same PR.

### PR description template

Fill in every section. Tick the boxes that apply and delete the placeholder text.

```markdown
## What does this PR do?

Brief description of the change and its purpose.

## Related Issue

Closes #XX

## Changes Made

- [ ] ...

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change (alters a documented service contract)
- [ ] Documentation update

## Contract Impact

- [ ] No change to the communication contract
- [ ] Contract changed — README and the affected service READMEs are updated in this PR

## How to Test

1. Check out this branch
2. Run the service and its dependencies
3. ...

## Checklist

- [ ] Self-reviewed the diff
- [ ] No secrets, `.env` files or `node_modules` committed
- [ ] Tests added for new behaviour and passing locally
- [ ] Documentation updated where needed
```

---

## 4. Testing before a PR

- Every new endpoint needs at least one success-path test and one test for its documented error response.
- Minimum **70 %** unit test coverage per service.
- Idempotent `event_id` endpoints (currency adjustment, XP award, ownership transfer, raid damage) need a test proving a repeated call does not apply the effect twice.
- Cross-service flows need integration tests: battle completion (currency + XP + capture), raid completion (reward distribution), proximity → notification.
- CI runs the test suite on every PR, and a failing suite blocks the merge.

---

## 5. Versioning & releases

Semantic Versioning (**MAJOR.MINOR.PATCH**) per service:

- **MAJOR**: breaking contract change (removed endpoint, changed response shape, renamed field).
- **MINOR**: backward-compatible addition (new endpoint, optional field, notification type).
- **PATCH**: bug fix or internal change with no contract impact.

Milestones are tagged on `main` as `v1.0-lab1`, `v2.0-lab2`, …

---

## 6. Checklist before every commit / PR

1. Am I on a correctly named feature branch off `develop` (not `main` / `develop`)?
2. Is the commit message one short imperative line, with no AI attribution?
3. Is the diff free of secrets and `.env` files?
4. Did a service contract change? If so, README.md and the service README are updated.
5. Does the PR target `develop`, with a short imperative title and the full template filled in?
