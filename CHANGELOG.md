# Changelog

## 0.2.0

- Resolve commit author to Redmine user by email (case-insensitive), falling back to username, then to `User.anonymous`.
- Always include an `Author: name <email>` attribution line in the journal note, regardless of match outcome.
- Render the full commit message body (no first-line truncation) as a blockquote, branching on `Setting.text_formatting` for markdown vs textile output, with a byte-safe 60 000-byte cap to stay within `journals.notes` column limits.
- Pull request events attribute to the PR opener via the `pull_request.user` payload field.
- Save retries as `User.anonymous` if the resolved user lacks permission to comment on the target issue; the status change (close/reopen) is preserved across the retry.

## 0.1.0

- Initial release.
