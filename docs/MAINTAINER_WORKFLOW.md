# Maintainer Workflow

This document describes the publication and merge requirements for
the pmelendez2/hailort public repository.

## Development branches

- Create changes on feature or fix branches.
- Do not push directly to protected main.
- Sign developer commits using a GitHub-registered signing key.
- Run required preflight checks.
- Publish feature branches using the PUBLISH confirmation.

## Required validation

Before publication:

    bash scripts/preflight-mps.sh --worktree
    git diff --check

Before committing:

    bash scripts/preflight-mps.sh --staged
    git diff --cached --check

After committing:

    git verify-commit HEAD
    bash scripts/preflight-mps.sh --committed

## Publishing

Publish the feature branch using the configured Git hooks:

    git -c core.hooksPath=.githooks push fork BRANCH_NAME

Review the publication prompt and type PUBLISH to confirm.

## Pull requests

All changes to main require pull requests.

Required CI checks:

- isolated (amd64)
- isolated (arm64)

Both checks must pass before merging.

## Merge policy

Use conventional pull-request merge commits:

    gh pr merge PR_NUMBER --repo pmelendez2/hailort --merge

Do not use rebase or squash merges.

Conventional merge commits preserve the original signed developer
commits.

Protected main requires verified commit signatures.

## Branch protection

The default branch requires:

- Pull requests.
- Verified commit signatures.
- Both native CI checks.
- Strict status-check enforcement.
- Conversation resolution.
- Administrator enforcement.

Force pushes and deletion are prohibited.

Linear history is not required because conventional merge commits
are permitted.

## Post-merge verification

Verify the pull-request state:

    gh pr view PR_NUMBER --repo pmelendez2/hailort

Inspect signatures after updating local references:

    git fetch fork main
    git log fork/main -10 --format='%h %G? %s'

G indicates a valid signature.
N indicates an unsigned commit.

Existing unsigned historical commits are not rewritten.

## Release requirements

Successful native compilation does not establish Hailo-8 hardware
runtime correctness.

Complete hardware validation before declaring an MPS release
production ready.
