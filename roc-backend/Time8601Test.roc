    ## ISO-8601 formatting tests. The vectors are known epoch instants checked against `date -u`.
    ## They live in their own file because `expect` blocks that call a function are reported as build
    ## diagnostics when the module is imported by the app. Run them with:
    ##
    ##     roc test Time8601Test.roc

    import Time8601

    Time8601Test := [].{}

    expect Time8601.from_unix_seconds(0) == "1970-01-01T00:00:00Z"
    expect Time8601.from_unix_seconds(1704067200) == "2024-01-01T00:00:00Z"
    # A leap day, and an instant with a clock rather than midnight.
    expect Time8601.from_unix_seconds(1709164800) == "2024-02-29T00:00:00Z"
    expect Time8601.from_unix_seconds(1730438774) == "2024-11-01T05:26:14Z"
    expect Time8601.from_unix_seconds(1735689600) == "2025-01-01T00:00:00Z"
    # The trailing second of a leap year, 23:59:59, still lands inside it (no off-by-one epoch day).
    expect Time8601.from_unix_seconds(1735689599) == "2024-12-31T23:59:59Z"