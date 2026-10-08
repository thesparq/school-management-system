Time8601 := [].{
    ## ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`) for a Unix timestamp in whole seconds.
    ##
    ## basic-webserver 0.17 dropped the platform's old `pf.Utc` module; `pf.UnixTime` hands out whole
    ## seconds since the epoch and leaves the calendar to the caller. This is the smallest pure
    ## calendar that works: Howard Hinnant's civil-from-days (days since 1970-01-01 to
    ## {year, month, day}), then the clock from the second-of-day.
    from_unix_seconds : I64 -> Str
    from_unix_seconds = |seconds| {
    days = seconds / 86400
    day_seconds = seconds % 86400
    { year, month, day } = civil_from_days(days)
    hour = day_seconds / 3600
    minute = (day_seconds % 3600) / 60
    second = day_seconds % 60

    "${I64.to_str(year)}-${two_digits(month)}-${two_digits(day)}T${two_digits(hour)}:${two_digits(minute)}:${two_digits(second)}Z"
}

    civil_from_days : I64 -> { year : I64, month : I64, day : I64 }
    civil_from_days = |z| {
    k = z + 719468
    era = (if k >= 0 { k } else { k - 146096 }) / 146097
    doe = k - era * 146097
    yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    mp = (5 * doy + 2) / 153
    d = doy - (153 * mp + 2) / 5 + 1
    m = if mp < 10 { mp + 3 } else { mp - 9 }

    { year: if m <= 2 { y + 1 } else { y }, month: m, day: d }
}

    two_digits : I64 -> Str
    two_digits = |n| {
        digits = I64.to_str(n)
        if n < 10 { "0${digits}" } else { digits }
    }
}