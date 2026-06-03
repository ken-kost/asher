# Integration tests hit the live GitHub API; excluded by default.
# Run them with `mix test --include integration`.
ExUnit.start(exclude: [:integration])
