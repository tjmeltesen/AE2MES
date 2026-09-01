Feature: Cloud assignment parsing

  Scenario: Parse assignment list from cloud JSON
    Given cloud assignment JSON
    When I parse assignment list from JSON
    Then there should be 1 assignment
    And assignment job id should be "job-7f3a"
    And assignment step count should be 2
    And assignment step 1 type should be "wait"
    And assignment step 2 type should be "transfer"

  Scenario: HardwareContext resolves registry keys
    Given cloud assignment JSON
    When I parse assignment list from JSON
    And a registry from the parsed assignment
    Then hardware context should resolve transposer to "def-456"
    When I load machine from hardware context
    Then machine address should be "abc-123"
