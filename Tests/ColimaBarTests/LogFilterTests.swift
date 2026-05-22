// Tests/ColimaBarTests/LogFilterTests.swift
import Foundation
import ColimaBarCore

func test_logFilter_errorLevel() {
    let lines = ["2024-01-01 ERROR: connection refused", "2024-01-01 normal log"]
    let result = LogFilter.apply(lines: lines, query: "")
    checkEqual(result[0].level, LogLevel.error, "LogFilter: ERROR line → .error level")
    checkEqual(result[1].level, LogLevel.normal, "LogFilter: normal line → .normal level")
}

func test_logFilter_warnLevel() {
    let lines = ["WARN: disk almost full", "INFO: all good"]
    let result = LogFilter.apply(lines: lines, query: "")
    checkEqual(result[0].level, LogLevel.warning, "LogFilter: WARN line → .warning")
    checkEqual(result[1].level, LogLevel.normal,  "LogFilter: INFO line → .normal")
}

func test_logFilter_successLevel() {
    let lines = ["SUCCESS: deployment complete", "OK: health check passed"]
    let result = LogFilter.apply(lines: lines, query: "")
    checkEqual(result[0].level, LogLevel.success, "LogFilter: SUCCESS line → .success")
    checkEqual(result[1].level, LogLevel.success, "LogFilter: OK line → .success")
}

func test_logFilter_queryFiltersLines() {
    let lines = ["ERROR: foo failed", "INFO: bar ok", "ERROR: baz failed"]
    let result = LogFilter.apply(lines: lines, query: "foo")
    checkEqual(result.count, 1, "LogFilter: query 'foo' → 1 match")
    checkEqual(result[0].text, "ERROR: foo failed", "LogFilter: correct line returned")
}

func test_logFilter_queryCaseInsensitive() {
    let lines = ["ERROR: FOO failed", "info: foo ok"]
    let result = LogFilter.apply(lines: lines, query: "foo")
    checkEqual(result.count, 2, "LogFilter: query is case-insensitive")
}

func test_logFilter_emptyQuery_returnsAll() {
    let lines = ["line1", "line2", "line3"]
    let result = LogFilter.apply(lines: lines, query: "")
    checkEqual(result.count, 3, "LogFilter: empty query returns all lines")
}

func test_logFilter_extractErrorLines() {
    let lines = ["INFO: ok", "ERROR: crash", "WARN: slow", "ERROR: timeout", "INFO: retry"]
    let errors = LogFilter.extractErrorLines(from: lines, max: 2)
    checkEqual(errors.count, 2, "extractErrorLines: max=2 returns 2")
    checkEqual(errors[0], "ERROR: crash", "extractErrorLines: first error line")
    checkEqual(errors[1], "ERROR: timeout", "extractErrorLines: second error line")
}
