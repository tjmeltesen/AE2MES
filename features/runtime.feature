Feature: Runtime tick cycle

  Scenario: Full tick with mock cloud
    Given a runtime with mock cloud
    When I tick runtime 1 times
    Then runtime active job count should be 1
    When I tick runtime 3 times
    Then runtime active job count should be 0
    And runtime tick cycle should complete without error
