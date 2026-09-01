Feature: Module loading and hardware parsing

  Scenario: All modules load
    Given all AE2-ES2 modules are loadable

  Scenario: Machine sensor parsing detects processing
    Given a machine with processing sensor lines
    When I parse machine sensor information
    Then machine progress should be 32 of 75
    And machine availability should be unavailable due to processing

  Scenario: Machine sensor parsing detects problems
    Given a machine with sensor problems 2
    When I parse machine sensor information
    Then machine availability should be unavailable due to problems

  Scenario: NetworkItems handles zero-indexed arrays
    When I format zero-indexed ME items
    Then formatted items count should be 2
    When I format zero-indexed ME fluids
    Then formatted fluids count should be 2
    When I format iterator-style ME items
    Then formatted items count should be 1

  Scenario: MeController buffer snapshot
    When I read ME controller buffer snapshot
    Then buffer snapshot should have at least 1 items and 1 fluids
