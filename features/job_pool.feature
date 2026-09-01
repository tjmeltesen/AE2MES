Feature: Job pool concurrency

  Scenario: Concurrent jobs on two machines
    Given an empty job pool
    When I spawn job "job-A" on "machine-lathe"
    Then spawn should succeed
    And active job count should be 1
    When I spawn job "job-B" on "machine-assembler"
    Then spawn should succeed
    And active job count should be 2
    When I spawn job "job-A-dup" on "machine-lathe"
    Then spawn should fail
    When I tick the job pool until 2 jobs complete
    Then completed jobs count should be 2
    And faulted jobs count should be 0
