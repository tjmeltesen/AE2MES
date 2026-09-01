Feature: JSON encoding and decoding

  Scenario: Decode primitives
    Given JSON input "null"
    When I decode the JSON input
    Then the decoded value should equal null
    Given JSON input "true"
    When I decode the JSON input
    Then the decoded value should equal true
    Given JSON input "42"
    When I decode the JSON input
    Then the decoded value should equal 42

  Scenario: Decode object with whitespace
    Given JSON input "  { \"a\" : 1 }  "
    When I decode the JSON input
    Then the decoded value should equal {"a":1}

  Scenario: Decode escaped string
    Given JSON input "\"say \\\"hi\\\"\""
    When I decode the JSON input
    Then the decoded value should equal "say \"hi\""

  Scenario: Decode nested structure
    Given JSON input "{\"user\":{\"id\":7,\"name\":\"alice\"},\"tags\":[\"a\",\"b\"]}"
    When I decode the JSON input
    Then the decoded value should equal {"user":{"id":7,"name":"alice"},"tags":["a","b"]}

  Scenario: Encode primitives
    Given JSON value true
    When I encode the JSON value
    Then the encoded value should be "true"
    Given JSON value 42
    When I encode the JSON value
    Then the encoded value should be "42"

  Scenario: Round-trip nested telemetry structure
    Given a JSON table
    And table field "schemaVersion" is 1
    And table field "brokerId" is "broker-alpha"
    And table field "queueLength" is 3
  When I round-trip the JSON value
  Then the round-tripped value should equal the original

  Scenario: Reject trailing garbage on decode
    Given JSON input "{\"a\":1}extra"
    When decoding should fail

  Scenario: Reject unsupported type on encode
    Given an unsupported JSON value type
    When encoding should fail
