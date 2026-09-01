Feature: Node sensor discovery

  Scenario: Discover machines and merge busy flags
    Given a node sensor with ME controller
    When I scan machines
    Then discovered machine count should be 2
    When job pool has busy machine "machine-lathe"
    And I merge job pool busy flags
    Then machine "machine-lathe" should be busy
    When I tick node sensor
    Then node sensor should have pending request
    And buffer snapshot should have at least 1 items
