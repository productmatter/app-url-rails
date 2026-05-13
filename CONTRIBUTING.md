# Contributing to tunnel-url-rails

Thanks for considering a contribution. Here's what you need to know.

## Setup

```bash
git clone https://github.com/jonathansimmons/tunnel-url-rails.git
cd tunnel-url-rails
bundle install
```

Requires Ruby 3.2+.

## Making changes

1. Fork the repo and create a branch from `main`.
2. Write tests for new behavior.
3. Run `gem build tunnel-url-rails.gemspec --strict` to validate the gemspec.
4. Open a pull request with a clear description of the change and why it's needed.

## Pull request expectations

- One logical change per PR.
- Include a test plan in the PR description.
- Keep commits focused — squash fixups before requesting review.

## Reporting bugs

Open an issue with steps to reproduce, expected behavior, and actual behavior. Include your Ruby and Rails versions.

## Security vulnerabilities

Please report security issues privately — see [SECURITY.md](SECURITY.md).
