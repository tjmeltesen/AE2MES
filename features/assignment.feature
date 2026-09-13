Feature: Cloud assignment parsing

  Scenario: Parse assignment list from cloud JSON
    Given cloud assignment JSON
    When I parse assignment list from JSON
    Then there should be 1 assignment
    And assignment job id should be "job-7f3a"
    And assignment step count should be 2
    And assignment step 1 type should be "wait"
    And assignment step 2 type should be "transfer"
