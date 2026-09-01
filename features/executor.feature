Feature: Executor step sequences

  Scenario: Wait-only sequence completes
    Given a wait-only assignment with 2 steps
    When I begin the executor
    And the executor ticks until inactive
    Then the executor phase should be "DONE"
    And the result should be ok

  Scenario: Wait ticks sequence completes
    Given a wait assignment with 2 ticks
    When I begin the executor
    And the executor ticks until inactive
    Then the executor phase should be "DONE"
    And the result should be ok

  Scenario: Transfer completes
    Given a transfer assignment with sides
    When I begin the executor
    And the executor ticks until inactive
    Then the executor phase should be "DONE"
    And the result should be ok

  Scenario: Configure and clear completes
    Given a configure and clear assignment
    When I begin the executor
    And the executor ticks until inactive
    Then the executor phase should be "DONE"
    And the result should be ok

  Scenario: Process poll completes when machine stops
    Given a process assignment with timeout 10
    And machine is active during process step
    When I begin the executor
    And the executor ticks 2 times
    And machine becomes inactive
    And the executor ticks 2 times
    Then the executor phase should be "DONE"
    And the result should be ok

  Scenario: Transfer faults without sides
    Given a transfer assignment missing fromSide and toSide
    When I begin the executor
    And the executor ticks once
    Then the executor phase should be "FAULTED"

  Scenario: Transfer zero items faults
    Given a transfer assignment with sides and zero moved
    When I begin the executor
    And the executor ticks until inactive
    Then the executor phase should be "FAULTED"
