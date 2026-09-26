# Contributing to app-url-rails

Thanks for considering a contribution. Here's what you need to know.

## Setup

```bash
git clone https://github.com/productmatter/app-url-rails.git
cd app-url-rails
bundle install
```

Requires Ruby 3.2+. The AppUrl 2.0 test matrix is Rails 8.0 and 8.1 on
Ruby 3.2 and 3.4, with one Gemfile per Rails line.

## Making changes

1. Fork the repo and create a branch from `main`.
2. Write tests for new behavior.
3. Run the test suite for each supported Rails line:

   ```bash
   BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle install
   BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test
   BUNDLE_GEMFILE=gemfiles/rails_8_1.gemfile bundle install
   BUNDLE_GEMFILE=gemfiles/rails_8_1.gemfile bundle exec rake test
   ```

   Repeat on Ruby 3.2 and Ruby 3.4; CI exercises all four combinations. The
   integration tests boot isolated apps without a database or network listener.

4. Run `gem build app-url-rails.gemspec --strict` to validate the gemspec.
5. Run `specline check .` to validate the documentation structure.
6. Open a pull request with a clear description of the change and why it's needed.

## Pull request expectations

- One logical change per PR.
- Include a test plan in the PR description.
- Keep commits focused — squash fixups before requesting review.

## Reporting bugs

Open an issue with steps to reproduce, expected behavior, and actual behavior. Include your Ruby and Rails versions.

## Security vulnerabilities

Please report security issues privately — see [SECURITY.md](SECURITY.md).
